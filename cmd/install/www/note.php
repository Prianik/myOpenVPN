<?php
$note = '/etc/openvpn/note.txt';
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
