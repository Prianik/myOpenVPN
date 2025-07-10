<?php
date_default_timezone_set('Europe/Moscow');
$firma = file_get_contents('/etc/openvpn/firma.txt');
?>

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Мониторинг сетевой активности</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f0f2f5;
            color: #333;
        }
        h1 {
            font-size: 26px;
            color: #2c3e50;
            text-align: center;
            margin-bottom: 30px;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.1);
        }
        h2 {
            font-size: 20px;
            color: #34495e;
            margin-top: 30px;
            margin-bottom: 15px;
        }
        .filter-form {
            margin-bottom: 30px;
            padding: 20px;
            background-color: #ffffff;
            border-radius: 8px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        .filter-form label {
            font-size: 14px;
            margin-right: 10px;
            color: #555;
        }
        .filter-form input,
        .filter-form select {
            font-size: 14px;
            padding: 5px;
            margin-right: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        .filter-form input[type="submit"] {
            background-color: #3498db;
            color: white;
            border: none;
            padding: 8px 15px;
            cursor: pointer;
            transition: background-color 0.3s;
        }
        .filter-form input[type="submit"]:hover {
            background-color: #2980b9;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 30px;
            background-color: #ffffff;
            border-radius: 8px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        th, td {
            border: 1px solid #e0e0e0;
            padding: 12px;
            text-align: left;
            font-size: 14px;
        }
        th {
            background-color: #ecf0f1;
            color: #2c3e50;
            font-weight: bold;
        }
        tr:nth-child(even) {
            background-color: #f9fbfc;
        }
        tr:hover {
            background-color: #f1f3f5;
            transition: background-color 0.2s;
        }
        .status-up {
            color: green;
        }
        .status-block {
            color: red;
        }
        p {
            font-size: 14px;
            color: #7f8c8d;
            text-align: center;
            padding: 15px;
            background-color: #ffffff;
            border-radius: 8px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <h1>Мониторинг сетевой активности <?php echo $firma; ?></h1>

    <div class="filter-form">
        <form method="GET">
            <?php
                $default_start_date = date('Y-m-01');
                $default_end_date   = date('Y-m-d');
                $start_date = isset($_GET['start_date']) ? $_GET['start_date'] : $default_start_date;
                $end_date   = isset($_GET['end_date']) ? $_GET['end_date'] : $default_end_date;
            ?>
            <label>Дата начала:</label>
            <input type="date" name="start_date" value="<?php echo $start_date; ?>">
            <label>Дата окончания:</label>
            <input type="date" name="end_date" value="<?php echo $end_date; ?>">
            <label>Пользователь:</label>
            <select name="user" onchange="this.form.submit();">
                <option value="">Выберите пользователя</option>
                <option value="all" <?php echo (isset($_GET['user']) && $_GET['user'] === 'all') ? 'selected' : ''; ?>>
                    -Показать всех пользователей-
                </option>
                <option value="online" <?php echo (isset($_GET['user']) && $_GET['user'] === 'online') ? 'selected' : ''; ?>>
                    -- Онлайн пользователи --
                </option>
                <?php
                    $log_file_path    = '/var/log/openvpn/client-connect.log';
                    $log_lines        = file($log_file_path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                    $unique_usernames = array_unique(array_map(function($line) {
                        $columns = preg_split('/\s+/', trim($line));
                        return $columns[2];
                    }, $log_lines));
                    sort($unique_usernames);

                    foreach ($unique_usernames as $username) {
                        $is_selected = (isset($_GET['user']) && $_GET['user'] === $username) ? 'selected' : '';
                        echo "<option value='$username' $is_selected>$username</option>";
                    }
                ?>
            </select>
            <input type="submit" value="Показать">
        </form>
    </div>

<?php
    function parseAndGroupLogData($file_path) {
        $grouped_data = [];
        if (file_exists($file_path)) {
            $lines = file($file_path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                $columns = preg_split('/\s+/', trim($line));
                if (count($columns) >= 7) {
                    $username = $columns[2];
                    $grouped_data[$username][] = [
                        'date'        => $columns[0],
                        'time'        => $columns[1],
                        'user'        => $columns[2],
                        'source_ip'   => $columns[3],
                        'assigned_ip' => $columns[5],
                        'status'      => $columns[6]
                    ];
                }
            }
        } else {
            echo "<p>Ошибка: Файл не найден по пути $file_path.</p>";
        }
        return $grouped_data;
    }

    function filterByDateRange($data, $start_date, $end_date) {
        if (!$start_date || !$end_date) {
            return $data;
        }
        foreach ($data as $username => $records) {
            $filtered_records = array_filter($records, function($record) use ($start_date, $end_date) {
                return $record['date'] >= $start_date && $record['date'] <= $end_date;
            });
            $data[$username] = array_values($filtered_records);
        }
        return $data;
    }

    $connect_log_path  = '/var/log/openvpn/client-connect.log';
    $grouped_log_data  = parseAndGroupLogData($connect_log_path);
    $start_date_filter = isset($_GET['start_date']) ? $_GET['start_date'] : null;
    $end_date_filter   = isset($_GET['end_date']) ? $_GET['end_date'] : null;
    $selected_user     = isset($_GET['user']) ? $_GET['user'] : null;

    $filtered_log_data = filterByDateRange($grouped_log_data, $start_date_filter, $end_date_filter);

    if (!empty($filtered_log_data)) {
        ksort($filtered_log_data);

        if ($selected_user) {
            if ($selected_user === 'all') {
                foreach ($filtered_log_data as $username => $records) {
                    if (!empty($records)) {
                        echo "<h2>$username</h2>";
                        echo "<table>";
                        echo "<tr>
                                <th>Дата и время</th>
                                <th>IP источник</th>
                                <th>Назначенный IP</th>
                                <th>Статус</th>
                              </tr>";
                        foreach ($records as $record) {
                            $status_class = ($record['status'] === 'UP') ? 'status-up' :
                                           (($record['status'] === 'BLOCK') ? 'status-block' : '');
                            echo "<tr class='$status_class'>";
                            echo "<td>{$record['date']} {$record['time']}</td>";
                            echo "<td>{$record['source_ip']}</td>";
                            echo "<td>{$record['assigned_ip']}</td>";
                            echo "<td>{$record['status']}</td>";
                            echo "</tr>";
                        }
                        echo "</table>";
                    }
                }
            } elseif ($selected_user === 'online') {
                include 'online_users.php';
            } elseif (isset($filtered_log_data[$selected_user])) {
                if (!empty($filtered_log_data[$selected_user])) {
                    echo "<h2>$selected_user</h2>";
                    echo "<table>";
                    echo "<tr>
                            <th>Дата и время</th>
                            <th>IP источник</th>
                            <th>Назначенный IP</th>
                            <th>Статус</th>
                          </tr>";
                    foreach ($filtered_log_data[$selected_user] as $record) {
                        $status_class = ($record['status'] === 'UP') ? 'status-up' :
                                       (($record['status'] === 'BLOCK') ? 'status-block' : '');
                        echo "<tr class='$status_class'>";
                        echo "<td>{$record['date']} {$record['time']}</td>";
                        echo "<td>{$record['source_ip']}</td>";
                        echo "<td>{$record['assigned_ip']}</td>";
                        echo "<td>{$record['status']}</td>";
                        echo "</tr>";
                    }
                    echo "</table>";
                } else {
                    echo "<p>Данные для пользователя $selected_user не найдены.</p>";
                }
            }
        }
    } else {
        echo "<p>Данные не найдены или файл не удалось прочитать.</p>";
    }
?>
</body>
</html>
