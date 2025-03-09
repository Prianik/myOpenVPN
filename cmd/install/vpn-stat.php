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
        /* Стили для страницы */
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
        .on {
            color: green;
            font-weight: bold;
        }
        .off {
            color: red;
            font-weight: bold;
        }
        .checkbox {
            text-align: center;
        }
    </style>
    <!-- Подключаем jQuery для работы с AJAX -->
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
</head>
<body>
    <h1>Список пользователей OpenVPN <?php echo $firma; ?></h1>
    <table>
        <thead>
            <tr>
                <th>Пользователь</th>
                <th>Статус</th>
                <th>Активен</th>
            </tr>
        </thead>
        <tbody>
            <?php
            // Путь к файлу user-vpn.txt
            $file_path = '/etc/openvpn/cmd/user-vpn.txt';

            // Проверяем, существует ли файл
            if (file_exists($file_path)) {
                // Открываем файл для чтения
                $file = fopen($file_path, 'r');

                // Массив для хранения данных о пользователях
                $users = [];

                // Читаем файл построчно
                while (($line = fgets($file)) !== false) {
                    // Разделяем строку на имя пользователя и статус
                    list($username, $status) = explode(' ', trim($line));

                    // Добавляем данные в массив
                    $users[] = [
                        'username' => $username,
                        'status' => $status
                    ];
                }

                // Закрываем файл
                fclose($file);

                // Сортируем массив по имени пользователя
                usort($users, function($a, $b) {
                    return strcmp($a['username'], $b['username']);
                });

                // Выводим отсортированные данные
                foreach ($users as $user) {
                    $username = $user['username'];
                    $status = $user['status'];

               // Пропускаем пользователя с именем "sector"
               if ($username === 'sector') {
                 continue;
                }



                    // Определяем цвет и текст статуса
                    if ($status == 1) {
                        $status_text = '<span class="on">ON</span>';
                        $checked = 'checked';
                    } else {
                        $status_text = '<span class="off">OFF</span>';
                        $checked = '';
                    }

                    // Выводим строку таблицы
                    echo "<tr>
                            <td>$username</td>
                            <td id='status-$username'>$status_text</td>
                            <td class='checkbox'>
                                <input type='checkbox' class='user-checkbox' data-username='$username' $checked>
                            </td>
                          </tr>";
                }
            } else {
                // Если файл не найден, выводим сообщение
                echo "<tr><td colspan='3'>Файл $file_path не найден.</td></tr>";
            }
            ?>
        </tbody>
    </table>

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
        // Обработка изменения состояния чекбокса
        $(document).ready(function() {
            $('.user-checkbox').change(function() {
                // Получаем имя пользователя и новое состояние чекбокса
                const username = $(this).data('username');
                const isActive = $(this).is(':checked') ? 1 : 0;

                // Отправка данных на сервер через AJAX
                $.ajax({
                    url: 'update_status.php', // Файл для обработки запроса
                    method: 'POST', // Метод HTTP-запроса
                    data: { username: username, status: isActive }, // Данные для отправки
                    success: function(response) {
                        // Обновление статуса на странице
                        const statusCell = $('#status-' + username);
                        if (isActive == 1) {
                            statusCell.html('<span class="on">ON</span>');
                        } else {
                            statusCell.html('<span class="off">OFF</span>');
                        }
                    },
                    error: function() {
                        // Обработка ошибки
                        alert('Ошибка при обновлении статуса.');
                    }
                });
            });
        });
    </script>
</body>
</html>

