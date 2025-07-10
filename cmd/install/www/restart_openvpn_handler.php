
<?php
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit("Метод не разрешен");
}

// Проверка прав доступа (можно усилить при необходимости)
if (!function_exists('shell_exec')) {
    http_response_code(500);
    exit("Функция shell_exec отключена");
}

// Команда для перезагрузки OpenVPN (может отличаться в зависимости от вашей системы)
$command = "sudo systemctl restart openvpn";
// Или альтернативные варианты:
// $command = "sudo service openvpn restart";
// $command = "sudo /etc/init.d/openvpn restart";

$output = shell_exec($command . ' 2>&1');

if ($output === null) {
    echo "success";
} else {
    http_response_code(500);
    exit("Ошибка при перезагрузке: " . $output);
}
?>
