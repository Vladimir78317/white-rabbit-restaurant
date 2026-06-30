using WhiteRabbitRestaurant.Services;

namespace WhiteRabbitRestaurant.Forms;

public sealed class RegistrationForm : Form
{
    private readonly TextBox _login = new() { PlaceholderText = "Логин", Width = 300 };
    private readonly TextBox _password = new() { PlaceholderText = "Пароль (минимум 6 символов)", Width = 300, UseSystemPasswordChar = true };
    private readonly TextBox _lastName = new() { PlaceholderText = "Фамилия", Width = 300 };
    private readonly TextBox _firstName = new() { PlaceholderText = "Имя", Width = 300 };
    private readonly TextBox _phone = new() { PlaceholderText = "Телефон", Width = 300 };
    private readonly Label _status = new() { AutoSize = true, MaximumSize = new Size(300, 0), ForeColor = Color.Firebrick };
    private readonly Button _register;

    public RegistrationForm()
    {
        Text = "White Rabbit — регистрация";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(430, 510);
        BackColor = Color.FromArgb(250, 248, 246);

        _register = new Button
        {
            Text = "Создать аккаунт",
            Width = 300,
            Height = 38,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            BackColor = Color.FromArgb(152, 36, 43),
            ForeColor = Color.White,
            Cursor = Cursors.Hand
        };
        _register.FlatAppearance.BorderColor = Color.FromArgb(152,36,43);
        _register.Click += async (_, _) => await RegisterAsync();

        var card = new Panel { BackColor = Color.White, Size = new Size(360, 422), Location = new Point(35, 42), BorderStyle = BorderStyle.FixedSingle };
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(30, 26, 30, 20)
        };
        panel.Controls.AddRange(new Control[]
        {
            new Label { Text = "РЕГИСТРАЦИЯ", Font = new Font("Segoe UI", 17, FontStyle.Bold), AutoSize = true, ForeColor = Color.FromArgb(35,35,35) },
            new Label { Text = "После регистрации вы сможете бронировать столик и делать заказ.", AutoSize = true, MaximumSize = new Size(300, 0), ForeColor = Color.DimGray, Margin = new Padding(3, 0, 3, 14) },
            _login, new Label { Height = 7 }, _password, new Label { Height = 7 }, _lastName, new Label { Height = 7 }, _firstName, new Label { Height = 7 }, _phone, new Label { Height = 14 }, _register, _status
        });
        card.Controls.Add(panel);
        Controls.Add(card);
        AcceptButton = _register;
    }

    private async Task RegisterAsync()
    {
        try
        {
            if (new[] { _login.Text, _password.Text, _lastName.Text, _firstName.Text, _phone.Text }.Any(string.IsNullOrWhiteSpace))
                throw new InvalidOperationException("Заполните все поля.");
            _register.Enabled = false;
            _status.ForeColor = Color.DimGray;
            _status.Text = "Регистрация...";
            var message = await AuthService.RegisterClientAsync(
                _login.Text.Trim(), _password.Text, _lastName.Text.Trim(), _firstName.Text.Trim(), _phone.Text.Trim());
            MessageBox.Show(message, "White Rabbit", MessageBoxButtons.OK, MessageBoxIcon.Information);
            DialogResult = DialogResult.OK;
        }
        catch (Exception exception)
        {
            _status.ForeColor = Color.Firebrick;
            _status.Text = exception.Message;
        }
        finally
        {
            _register.Enabled = true;
        }
    }
}
