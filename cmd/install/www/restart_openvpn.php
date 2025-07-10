<!-- restart_openvpn.php -->
<div style="margin: 20px 0;">
    <button id="restart-openvpn" class="restart-btn">Перезагрузить OpenVPN</button>
    <span id="restart-status" style="margin-left: 10px;"></span>
</div>

<style>
    .restart-btn {
        padding: 5px 10px;
        background-color: #4CAF50;
        color: white;
        border: none;
        cursor: pointer;
        border-radius: 3px;
    }
    .restart-btn:hover {
        background-color: #45a049;
    }
    .restart-btn:disabled {
        background-color: #cccccc;
        cursor: not-allowed;
    }
</style>

<script>
    $(document).ready(function() {
        $('#restart-openvpn').click(function() {
            const $button = $(this);
            const $status = $('#restart-status');
            
            if (confirm('Вы уверены, что хотите перезагрузить OpenVPN сервер? Это может прервать текущие соединения.')) {
                $button.prop('disabled', true).text('Перезагрузка...');
                $status.text('Выполняется...');

                $.ajax({
                    url: 'restart_openvpn_handler.php',
                    method: 'POST',
                    success: function(response) {
                        if (response === 'success') {
                            $status.text('OpenVPN успешно перезагружен');
                            setTimeout(() => $status.text(''), 5000);
                        } else {
                            $status.text('Ошибка: ' + response);
                        }
                    },
                    error: function() {
                        $status.text('Ошибка при перезагрузке сервера');
                    },
                    complete: function() {
                        $button.prop('disabled', false).text('Перезагрузить OpenVPN');
                    }
                });
            }
        });
    });
</script>
