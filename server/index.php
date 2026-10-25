<?php
/**
 * The server's home page: what it is, and the address to enter in the
 * app. Nothing about the families it serves.
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/i18n.php';

$installed = load_config() !== null;
page_start(t('brand'));
echo '<div class="card"><p>' . h(t('home_text')) . '</p></div>';
if (!$installed) {
    echo '<div class="card"><p>' . h(t('home_not_installed')) . '</p>'
        . (is_file(__DIR__ . '/install.php')
            ? '<a class="button" href="install.php?lang=' . lang() . '">' . h(t('home_install')) . '</a>'
            : '')
        . '</div>';
    page_end();
    exit;
}
echo '<div class="card"><h2>' . h(t('home_address')) . '</h2>'
    . '<p class="code">' . h(server_base() . '/api.php') . '</p>'
    . '<p class="muted">' . h(t('home_how')) . '</p></div>';
echo '<p><a href="admin.php?lang=' . lang() . '">' . h(t('home_admin')) . '</a></p>';
page_end();
