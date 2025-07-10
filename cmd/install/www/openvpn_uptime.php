<!-- openvpn_uptime_systemctl.php -->
<div style="margin: 20px 0;">

<?php
function getOpenVPNUptimeFromSystemctl() {
    $output = shell_exec('systemctl status openvpn 2>&1');

    if ($output === null) {
        return "Ошибка: Не удалось выполнить команду systemctl (возможно, shell_exec отключен или нет прав)";
    }

    $lines = explode("\n", $output);
    foreach ($lines as $line) {
        if (strpos($line, 'Active:') !== false) {
            // Разделяем строку по символу ";"
            $parts = explode(';', $line);
            if (count($parts) > 1) {
                $timeAgo = trim($parts[1]); // Убираем лишние пробелы
                return "Время работы OpenVPN: " . $timeAgo;
            }
        }
    }

    return "Ошибка: Не удалось извлечь время работы.";
}

$uptime = getOpenVPNUptimeFromSystemctl();
echo "<p>$uptime</p>";
?>

</div>
