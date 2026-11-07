package org.familyscreentime

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Parent mode opened with a fingerprint or the face, on a parent's device.
 *
 * The parent code itself is kept, encrypted with a key of Android's
 * keystore that only a strong biometric opens, for each use: a key that
 * never leaves the device's secure hardware. Opening it gives back the
 * code, which then goes the way of a typed code (it also opens the family's
 * signing key). A finger or a face added to the device since makes the key
 * unusable, so that it cannot be opened by someone just enrolled: the code
 * is asked again. The device's own screen lock code is never accepted in
 * place of the biometric: a child who knows it must not get in.
 *
 * Android 10 and later only: the library's older fingerprint dialog needs a
 * theme this app does not use.
 */
internal class BiometricUnlock(private val activity: FragmentActivity) {

    class Texts(val title: String, val subtitle: String?, val cancel: String)

    /** A strong biometric is enrolled and usable. */
    fun available(): Boolean =
        Build.VERSION.SDK_INT >= MIN_SDK &&
            BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS

    /** Encrypts [code] behind the biometric: `status`, and `seal` when ok. */
    fun seal(code: String, texts: Texts, done: (Map<String, Any?>) -> Unit) {
        if (!available()) return done(status(UNAVAILABLE))
        val cipher = try {
            forget()
            Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, newKey()) }
        } catch (e: Exception) {
            forget()
            return done(status(ERROR))
        }
        prompt(cipher, texts, done) { c ->
            val data = c.doFinal(code.toByteArray(Charsets.UTF_8))
            mapOf("status" to OK, "seal" to "${b64(c.iv)}:${b64(data)}")
        }
    }

    /** Decrypts a [seal] with the biometric: `status`, and `code` when ok. */
    fun open(seal: String, texts: Texts, done: (Map<String, Any?>) -> Unit) {
        if (!available()) return done(status(UNAVAILABLE))
        val parts = seal.split(':')
        val key = key()
        if (parts.size != 2 || key == null) return done(status(INVALIDATED))
        val iv: ByteArray
        val data: ByteArray
        try {
            iv = Base64.decode(parts[0], Base64.NO_WRAP)
            data = Base64.decode(parts[1], Base64.NO_WRAP)
        } catch (e: IllegalArgumentException) {
            return done(status(INVALIDATED))
        }
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // A finger or a face added, or the screen lock removed.
            forget()
            return done(status(INVALIDATED))
        } catch (e: Exception) {
            return done(status(ERROR))
        }
        prompt(cipher, texts, done) { c ->
            mapOf("status" to OK, "code" to String(c.doFinal(data), Charsets.UTF_8))
        }
    }

    /** The key goes: what it sealed can no longer be opened. */
    fun forget() {
        try {
            keyStore().deleteEntry(ALIAS)
        } catch (e: Exception) {
            // No key, nothing to forget.
        }
    }

    private fun prompt(
        cipher: Cipher,
        texts: Texts,
        done: (Map<String, Any?>) -> Unit,
        use: (Cipher) -> Map<String, Any?>,
    ) {
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(texts.title)
            .apply { texts.subtitle?.let { setSubtitle(it) } }
            .setNegativeButtonText(texts.cancel)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                val c = result.cryptoObject?.cipher ?: return done(status(ERROR))
                done(
                    try {
                        use(c)
                    } catch (e: Exception) {
                        status(ERROR)
                    },
                )
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                done(status(errorStatus(errorCode)))
            }

            // onAuthenticationFailed: a finger not recognised, the prompt
            // stays for another try.
        }
        try {
            BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
                .authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) {
            done(status(ERROR))
        }
    }

    private fun newKey(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= 30) {
                    // Each use, with a strong biometric only.
                    setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(-1)
                }
            }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            .apply { init(spec) }
            .generateKey()
    }

    private fun key(): SecretKey? = try {
        keyStore().getKey(ALIAS, null) as? SecretKey
    } catch (e: Exception) {
        null
    }

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun b64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)

    private fun status(s: String): Map<String, Any?> = mapOf("status" to s)

    private fun errorStatus(code: Int) = when (code) {
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_CANCELED,
        -> CANCELLED
        BiometricPrompt.ERROR_LOCKOUT,
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT,
        -> LOCKOUT
        BiometricPrompt.ERROR_NO_BIOMETRICS,
        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_HW_UNAVAILABLE,
        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
        -> UNAVAILABLE
        else -> ERROR
    }

    companion object {
        const val MIN_SDK = 29
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "parent-code"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128

        const val OK = "ok"
        const val CANCELLED = "cancelled"
        const val INVALIDATED = "invalidated"
        const val LOCKOUT = "lockout"
        const val UNAVAILABLE = "unavailable"
        const val ERROR = "error"
    }
}
