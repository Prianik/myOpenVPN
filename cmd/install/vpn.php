<?php
// Установка часового пояса (для примера, можно убрать, если задано в php.ini)
date_default_timezone_set('Europe/Moscow');
$firma = file_get_contents('/etc/openvpn/firma.txt');
?>

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Мониторинг сетевой активности</title>
    <style>
        /* Общий стиль страницы */
        body {
            font-family:      Arial, sans-serif;
            font-size:        14px;
            line-height:      1.6;
            margin:           0;
            padding:          20px;
            background-color: #f0f2f5;
            color:            #333;
        }

        /* Заголовок */
        h1 {
            font-size:     26px;
            color:         #2c3e50;
            text-align:    center;
            margin-bottom: 30px;
            text-shadow:   1px 1px 2px rgba(0,0,0,0.1);
        }

        h2 {
            font-size:     20px;
            color:         #34495e;
            margin-top:    30px;
            margin-bottom: 15px;
        }

        /* Стиль формы фильтрации */
        .filter-form {
            margin-bottom:  30px;
            padding:        20px;
            background-color: #ffffff;
            border-radius:  8px;
            box-shadow:     0 2px 5px rgba(0,0,0,0.1);
        }

        .filter-form label {
            font-size:   14px;
            margin-right: 10px;
            color:       #555;
        }

        .filter-form input,
        .filter-form select {
            font-size:   14px;
            padding:     5px;
            margin-right: 15px;
            border:      1px solid #ddd;
            border-radius: 4px;
        }

        .filter-form input[type="submit"] {
            background-color: #3498db;
            color:           white;
            border:          none;
            padding:         8px 15px;
            cursor:          pointer;
            transition:      background-color 0.3s;
        }

        .filter-form input[type="submit"]:hover {
            background-color: #2980b9;
        }

        /* Стиль таблиц */
        table {
            border-collapse: collapse;
            width:          100%;
            margin-bottom:  30px;
            background-color: #ffffff;
            border-radius:  8px;
            box-shadow:     0 2px 5px rgba(0,0,0,0.1);
            overflow:       hidden;
        }

        th, td {
            border:      1px solid #e0e0e0;
            padding:     12px;
            text-align:  left;
            font-size:   14px;
        }

        th {
            background-color: #ecf0f1;
            color:           #2c3e50;
            font-weight:     bold;
        }

        tr:nth-child(even) {
            background-color: #f9fbfc;
        }

        tr:hover {
            background-color: #f1f3f5;
            transition:       background-color 0.2s;
        }

        /* Цвета для статусов */
        .status-up {
            color: green;
        }

        .status-block {
            color: red;
        }

        /* Стили для уведомлений */
        p {
            font-size:   14px;
            color:       #7f8c8d;
            text-align:  center;
            padding:     15px;
            background-color: #ffffff;
            border-radius: 8px;
            box-shadow:   0 2px 5px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <h1>Мониторинг сетевой активности <?php echo $firma; ?></h1>

    <!-- Форма фильтрации -->
    <div class="filter-form">
        <form method="GET">
            <?php
                // Установка значений дат по умолчанию для первой загрузки
                $default_start_date = date('Y-m-01'); // Начало текущего месяца
                $default_end_date   = date('Y-m-d');  // Текущая дата (сегодня)

                // Используем значения из GET или значения по умолчанию
                $start_date = isset($_GET['start_date']) ? $_GET['start_date'] : $default_start_date;
                $end_date   = isset($_GET['end_date']) ? $_GET['end_date'] : $default_end_date;
            ?>
            <label>Дата начала:</label>
            <input type="date"
                   name="start_date"
                   value="<?php echo $start_date; ?>">

            <label>Дата окончания:</label>
            <input type="date"
                   name="end_date"
                   value="<?php echo $end_date; ?>">

            <label>Пользователь:</label>
            <select name="user" onchange="this.form.submit();">
                <option value="">Выберите пользователя</option>
                <option value="all"
                        <?php echo (isset($_GET['user']) && $_GET['user'] === 'all') ? 'selected' : ''; ?>>
                    -Показать всех пользователей-
                </option>
                <option value="online"
                        <?php echo (isset($_GET['user']) && $_GET['user'] === 'online') ? 'selected' : ''; ?>>
                    -- Онлайн пользователи --
                </option>
                <?php
                    // --- Формирование списка пользователей из файла client-connect.log ---
                    // Путь к файлу логов подключений OpenVPN
                    $log_file_path    = '/var/log/openvpn/client-connect.log';
                    // Чтение всех строк из файла, игнорируя пустые
                    $log_lines        = file($log_file_path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                    // Извлечение уникальных имен пользователей (3-я колонка)
                    $unique_usernames = array_unique(array_map(function($line) {
                        $columns = preg_split('/\s+/', trim($line));
                        return $columns[2];
                    }, $log_lines));
                    // Сортировка имен по алфавиту
                    sort($unique_usernames);

                    // Вывод списка пользователей в выпадающий список
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
    // --- Функция: Парсинг и группировка данных из client-connect.log ---
    // Принимает путь к файлу и возвращает массив, сгруппированный по имени пользователя
    function parseAndGroupLogData($file_path) {
        $grouped_data = [];

        if (file_exists($file_path)) {
            $lines = file($file_path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

            foreach ($lines as $line) {
                $columns = preg_split('/\s+/', trim($line));
                // Проверяем, что строка содержит минимум 7 колонок
                if (count($columns) >= 7) {
                    $username = $columns[2];
                    $grouped_data[$username][] = [
                        'date'        => $columns[0],  // Дата
                        'time'        => $columns[1],  // Время
                        'user'        => $columns[2],  // Имя пользователя
                        'source_ip'   => $columns[3],  // IP-адрес источника
                        'assigned_ip' => $columns[5],  // Назначенный IP
                        'status'      => $columns[6]   // Статус (UP/DOWN/BLOCK)
                    ];
                }
            }
        } else {
            echo "<p>Ошибка: Файл не найден по пути $file_path.</p>";
        }

        return $grouped_data;
    }

    // --- Функция: Получение списка онлайн-пользователей из status.log ---
    // Извлекает данные из секции ROUTING TABLE
    function getOnlineUsers($file_path) {
        $online_users = [];

        if (file_exists($file_path)) {
            $lines = file($file_path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            $routing_section = false;

            foreach ($lines as $line) {
                // Начало секции ROUTING TABLE
                if (trim($line) === 'ROUTING TABLE') {
                    $routing_section = true;
                    continue;
                }
                // Конец секции
                if ($routing_section && (trim($line) === 'GLOBAL STATS' || trim($line) === 'END')) {
                    $routing_section = false;
                    break;
                }

                // Обработка строк из ROUTING TABLE (начинаются с IP-адреса 10.x.x.x)
                if ($routing_section && preg_match('/^10\./', $line)) {
                    $columns = explode(',', trim($line));
                    if (count($columns) >= 4) {
                        $assigned_ip  = $columns[0];              // Назначенный IP
                        $username     = $columns[1];              // Имя пользователя
                        $real_address = explode(':', $columns[2])[0]; // IP источника (без порта)

                        $online_users[$username] = [
                            'source_ip'   => $real_address,
                            'assigned_ip' => $assigned_ip
                        ];
                    }
                }
            }
        } else {
            echo "<p>Ошибка: Файл статуса не найден по пути $file_path.</p>";
        }

        return $online_users;
    }

    // --- Функция: Фильтрация данных по диапазону дат ---
    // Применяется только к данным из client-connect.log
    function filterByDateRange($data, $start_date, $end_date) {
        if (!$start_date || !$end_date) {
            return $data; // Если даты не заданы, возвращаем данные без фильтрации
        }

        foreach ($data as $username => $records) {
            $filtered_records = array_filter($records, function($record) use ($start_date, $end_date) {
                return $record['date'] >= $start_date && $record['date'] <= $end_date;
            });
            $data[$username] = array_values($filtered_records);
        }

        return $data;
    }

    // --- Основная логика обработки ---
    // Пути к файлам логов
    $connect_log_path  = '/var/log/openvpn/client-connect.log';
    $status_log_path   = '/var/log/openvpn/status.log';

    // Парсинг данных из client-connect.log
    $grouped_log_data  = parseAndGroupLogData($connect_log_path);

    // Получение параметров фильтра из GET
    $start_date_filter = isset($_GET['start_date']) ? $_GET['start_date'] : null;
    $end_date_filter   = isset($_GET['end_date']) ? $_GET['end_date'] : null;
    $selected_user     = isset($_GET['user']) ? $_GET['user'] : null;

    // Фильтрация данных по датам
    $filtered_log_data = filterByDateRange($grouped_log_data, $start_date_filter, $end_date_filter);

    // --- Вывод данных ---
    if (!empty($filtered_log_data)) {
        ksort($filtered_log_data); // Сортировка пользователей по алфавиту

        if ($selected_user) {
            // Вариант 1: Показать всех пользователей
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
            }
            // Вариант 2: Показать онлайн-пользователей из status.log
            elseif ($selected_user === 'online') {
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
            }
            // Вариант 3: Показать данные конкретного пользователя
            elseif (isset($filtered_log_data[$selected_user])) {
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
