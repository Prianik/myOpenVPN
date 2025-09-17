<?php
// Функция для получения онлайн-пользователей из status.log
function getOnlineUsers($file_path) {
    $online_users = [];

    if (file_exists($file_path)) {
        $lines = file($file_path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        $routing_section = false;

        foreach ($lines as $line) {
            if (trim($line) === 'ROUTING TABLE') {
                $routing_section = true;
                continue;
            }
            if ($routing_section && (trim($line) === 'GLOBAL STATS' || trim($line) === 'END')) {
                $routing_section = false;
                break;
            }

            if ($routing_section && preg_match('/^10\./', $line)) {
                $columns = explode(',', trim($line));
                if (count($columns) >= 4) {
                    $assigned_ip = $columns[0];
                    $username    = $columns[1];
                    $real_address = explode(':', $columns[2])[0];
                    
                    // Пропускаем пользователей, которые начинаются на sector или ##
                    if (strpos($username, 'sector') === 0 || strpos($username, '##') === 0) {
                        continue;
                    }

                    $online_users[$username] = [
                        'source_ip'   => $real_address,
                        'assigned_ip' => $assigned_ip,
                    ];
                }
            }
        }
    } else {
        echo "<p>Ошибка: Файл статуса не найден по пути $file_path.</p>";
    }

    return $online_users;
}

// Отображение онлайн-пользователей
$status_log_path = '/var/log/openvpn/status.log';
$online_users = getOnlineUsers($status_log_path);

if (!empty($online_users)) {
    echo "<h2>Пользователи онлайн</h2>";
    echo "<table>";
    echo "<tr>
            <th>Имя пользователя</th>
            <th>IP-адрес источника</th>
            <th>Назначенный IP</th>
          </tr>";

    foreach ($online_users as $username => $record) {
        echo "<tr class='status-up'>";
        echo "<td>$username</td>";
        echo "<td>{$record['source_ip']}</td>";
        echo "<td>{$record['assigned_ip']}</td>";
        echo "</tr>";
    }

    echo "</table>";
} else {
    echo "<p>Онлайн-пользователи не найдены.</p>";
}
?>
