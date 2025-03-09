<?php
$firma = file_get_contents('/etc/openvpn/firma.txt');
$note = '/etc/openvpn/note.txt';
?>

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Список пользователей OpenVPN</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
        }
        table {
            width: 50%;
            border-collapse: collapse;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border: 1px solid #ddd;
        }
        th {
            background-color: #f4f4f4;
        }
        .checkbox {
            text-align: center;
        }
        /* Стили для переключателя */
        .switch {
            position: relative;
            display: inline-block;
            width: 40px;
            height: 20px;
        }
        .switch input {
            opacity: 0;
            width: 0;
            height: 0;
        }
        .slider {
            position: absolute;
            cursor: pointer;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: #ccc;
            transition: .4s;
            border-radius: 20px;
        }
        .slider:before {
            position: absolute;
            content: "";
            height: 16px;
            width: 16px;
            left: 2px;
            bottom: 2px;
            background-color: white;
            transition: .4s;
            border-radius: 50%;
        }
        input:checked + .slider {
            background-color: #4CAF50; /* Зеленый цвет при включении */
        }
        input:checked + .slider:before {
            transform: translateX(20px);
        }
    </style>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
</head>
<body>
    <h1>Список пользователей OpenVPN <?php echo htmlspecialchars($firma); ?></h1>
    <table>
        <thead>
            <tr>
                <th>Пользователь</th>
                <th>Активен</th>
                <th>Заметки</th>
            </tr>
        </thead>
        <tbody>
            <?php
            $file_path = '/etc/openvpn/cmd/user-vpn.txt';

            if (file_exists($file_path)) {
                $file = fopen($file_path, 'r');
                $users = [];

                while (($line = fgets($file)) !== false) {
                    $parts = explode(' ', trim($line), 3);
                    $username = $parts[0];
                    $status = $parts[1];
                    $notes = isset($parts[2]) ? trim($parts[2]) : '';

                    if (str_starts_with($username, 'sector')) {
                        continue;
                    }

                    $users[] = [
                        'username' => $username,
                        'status' => $status,
                        'notes' => $notes
                    ];
                }
                fclose($file);

                usort($users, function($a, $b) {
                    return strcmp($a['username'], $b['username']);
                });

                foreach ($users as $user) {
                    $username = htmlspecialchars($user['username']);
                    $status = $user['status'];
                    $notes = htmlspecialchars($user['notes']);

                    $checked = $status == 1 ? 'checked' : '';

                    echo "<tr>
                            <td>$username</td>
                            <td class='checkbox'>
                                <label class='switch'>
                                    <input type='checkbox' class='user-switch' data-username='$username' $checked>
                                    <span class='slider'></span>
                                </label>
                            </td>
                            <td>$notes</td>
                          </tr>";
                }
            } else {
                echo "<tr><td colspan='3'>Файл $file_path не найден.</td></tr>";
            }
            ?>
        </tbody>
    </table>

<?php //include 'disable_all.php'; ?>
<?php include 'restart_openvpn.php'; ?>
<?php include 'stop_openvpn.php'; ?>
<?php include 'online_users.php'; ?>


<?php
echo "<pre>--note--</pre>";
$content = file_get_contents($note);

if ($content !== false) {
    $lines = explode("\n", $content);
    $filtered_lines = array_filter($lines, function($line) {
        $trimmed = trim($line);
        return !empty($trimmed) && !str_starts_with($trimmed, '#') && !str_starts_with($trimmed, '//');
    });
    sort($filtered_lines);
    echo "<pre>" . htmlspecialchars(implode("\n", $filtered_lines)) . "</pre>";
} else {
    echo "Не удалось прочитать файл";
}
echo "<pre>---</pre>";
?>

    <script>
        $(document).ready(function() {
            $('.user-switch').change(function() {
                const username = $(this).data('username');
                const isActive = $(this).is(':checked') ? 1 : 0;

                $.ajax({
                    url: 'update_status.php',
                    method: 'POST',
                    data: { username: username, status: isActive },
                    success: function(response) {
                        // Статус теперь виден только через переключатель
                    },
                    error: function() {
                        alert('Ошибка при обновлении статуса.');
                    }
                });
            });
        });
    </script>
</body>
</html>
