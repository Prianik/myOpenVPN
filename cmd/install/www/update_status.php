<?php
// Путь к файлу user-vpn.txt
$file_path = '/etc/openvpn/cmd/user-vpn.txt';

// Получаем данные из AJAX-запроса
$username = $_POST['username'];
$status = $_POST['status'];

// Проверяем, существует ли файл
if (!file_exists($file_path)) {
    echo 'Ошибка: Файл user-vpn.txt не найден.';
    exit;
}

// Читаем файл в массив
$lines = file($file_path);

// Обновляем статус пользователя
$updated = false;
foreach ($lines as &$line) {
    // Разделяем строку на имя пользователя, статус и комментарий
    $parts = explode(';', trim($line), 3);
    $current_username = $parts[0];
    
    // Если имя пользователя совпадает, обновляем статус
    if ($current_username === $username) {
        $current_comment = isset($parts[2]) ? $parts[2] : '';
        $line = "$username;$status;$current_comment" . PHP_EOL;
        $updated = true;
        break;
    }
}

// Если пользователь не найден, добавляем его в файл (сохраняем формат)
if (!$updated) {
    $lines[] = "$username;$status;" . PHP_EOL;
}

// Записываем обновленные данные обратно в файл
file_put_contents($file_path, $lines);

// Возвращаем успешный ответ
echo 'OK';
?>
