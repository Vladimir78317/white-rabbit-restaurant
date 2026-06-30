namespace WhiteRabbitRestaurant.Forms;

internal static class ReasonDialog
{
    public static string? Ask(IWin32Window owner, string title, string prompt)
    {
        using var dialog = new Form
        {
            Text = title,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MinimizeBox = false,
            MaximizeBox = false,
            ShowInTaskbar = false,
            ClientSize = new Size(470, 215)
        };

        var label = new Label
        {
            Text = prompt,
            AutoSize = false,
            Location = new Point(18, 15),
            Size = new Size(435, 44)
        };

        var text = new TextBox
        {
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            Location = new Point(18, 64),
            Size = new Size(435, 84),
            MaxLength = 500
        };

        var ok = new Button
        {
            Text = "Продолжить",
            DialogResult = DialogResult.OK,
            Location = new Point(265, 164),
            Size = new Size(92, 32)
        };
        var cancel = new Button
        {
            Text = "Отмена",
            DialogResult = DialogResult.Cancel,
            Location = new Point(362, 164),
            Size = new Size(92, 32)
        };

        dialog.AcceptButton = ok;
        dialog.CancelButton = cancel;
        dialog.Controls.AddRange(new Control[] { label, text, ok, cancel });

        return dialog.ShowDialog(owner) == DialogResult.OK ? text.Text.Trim() : null;
    }
}
