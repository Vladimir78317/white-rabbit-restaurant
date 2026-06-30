using System.Data;
using WhiteRabbitRestaurant.Models;
using WhiteRabbitRestaurant.Services;

namespace WhiteRabbitRestaurant.Forms;

public sealed class MainForm : Form
{
    private static readonly Color Accent = Color.FromArgb(152, 36, 43);
    private static readonly Color Surface = Color.FromArgb(250, 248, 246);
    private static readonly Color Ink = Color.FromArgb(35, 35, 35);

    private readonly UserSession _user;

    private readonly DataGridView _tablesGrid = CreateGrid();
    private readonly DataGridView _reservationsGrid = CreateGrid();
    private readonly DataGridView _waiterOrdersGrid = CreateGrid();
    private readonly DataGridView _waiterItemsGrid = CreateGrid();
    private readonly DataGridView _waiterReservationsGrid = CreateGrid();
    private readonly DataGridView _clientCartGrid = CreateGrid();
    private readonly DataGridView _kitchenOrdersGrid = CreateGrid();
    private readonly DataGridView _kitchenDishesGrid = CreateGrid();
    private readonly DataGridView _adminEmployeesGrid = CreateGrid();
    private readonly DataGridView _adminShiftsGrid = CreateGrid();
    private readonly DataGridView _adminSalesGrid = CreateGrid();
    private readonly DataGridView _adminStockGrid = CreateGrid();
    private readonly DataGridView _adminStockHistoryGrid = CreateGrid();
    private readonly DataGridView _clientOrderStatusesGrid = CreateGrid();
    private readonly DataGridView _adminOrderStatusesGrid = CreateGrid();
    private readonly DataGridView _adminTableOrderGrid = CreateGrid();

    // Интерактивные схемы столиков: вместо табличного представления для клиента, официанта и администратора.
    private readonly FlowLayoutPanel _reservationTableMap = CreateTableMapPanel();
    private readonly Label _reservationTableMapHint = new()
    {
        AutoSize = true,
        Text = "Выберите дату, время и число гостей — затем нажмите на свободный столик.",
        ForeColor = Color.DimGray,
        Padding = new Padding(20, 4, 0, 2)
    };
    private readonly FlowLayoutPanel _waiterTableMap = CreateTableMapPanel();
    private readonly Label _waiterTableMapHint = new()
    {
        Dock = DockStyle.Bottom,
        Height = 28,
        Text = "Откройте смену — назначенные столики появятся на схеме.",
        ForeColor = Color.DimGray,
        Padding = new Padding(8, 5, 8, 0)
    };
    private readonly FlowLayoutPanel _adminTableMap = CreateTableMapPanel();
    private readonly Label _adminTableMapHint = new()
    {
        Dock = DockStyle.Bottom,
        Height = 28,
        Text = "Нажмите «Обновить», чтобы увидеть актуальное состояние столиков.",
        ForeColor = Color.DimGray,
        Padding = new Padding(8, 5, 8, 0)
    };
    private readonly FlowLayoutPanel _adminReservationTableMap = CreateTableMapPanel();
    private readonly Label _adminReservationMapHint = new()
    {
        Dock = DockStyle.Bottom,
        Height = 28,
        Text = "Выберите дату, затем нажмите столик — ниже появятся все его брони за этот день.",
        ForeColor = Color.DimGray,
        Padding = new Padding(8, 5, 8, 0)
    };
    private readonly DateTimePicker _reservationDay = new()
    {
        Width = 135,
        Format = DateTimePickerFormat.Short,
        Value = DateTime.Today
    };
    private readonly DateTimePicker _waiterReservationDay = new()
    {
        Width = 135,
        Format = DateTimePickerFormat.Short,
        Value = DateTime.Today
    };
    private int? _selectedAdminReservationTableId;
    private int? _selectedAdminTableId;
    private int? _selectedWaiterTableId;
    private int? _selectedWaiterReservationTableId;
    private readonly Label _adminTableOrderHint = new()
    {
        AutoSize = true,
        Text = "Нажмите карточку занятого столика, чтобы увидеть его активный заказ.",
        ForeColor = Color.DimGray,
        Padding = new Padding(4, 6, 0, 0)
    };

    private readonly System.Windows.Forms.Timer _autoCloseTimer = new() { Interval = 60_000 };

    private readonly FlowLayoutPanel _waiterCards = CreateCardsPanel();
    private readonly FlowLayoutPanel _clientCards = CreateCardsPanel();

    private readonly TextBox _waiterSearch = new() { PlaceholderText = "Поиск блюда", Width = 240 };
    private readonly TextBox _clientSearch = new() { PlaceholderText = "Поиск блюда", Width = 240 };
    private readonly ComboBox _waiterTable = new() { Width = 230, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _clientTable = new() { Width = 230, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown _waiterGuests = new() { Minimum = 1, Maximum = 4, Value = 2, Width = 58 };
    private readonly NumericUpDown _clientGuests = new() { Minimum = 1, Maximum = 4, Value = 2, Width = 58 };

    private readonly Label _waiterOrderInfo = new() { AutoSize = true, Text = "Сначала создайте заказ", ForeColor = Color.DimGray, Padding = new Padding(4, 10, 0, 0) };
    private readonly Label _clientOrderInfo = new() { AutoSize = true, Text = "Выберите столик и начните заказ", ForeColor = Color.DimGray, Padding = new Padding(4, 10, 0, 0) };
    private Button? _waiterCreateOrderButton;
    private Button? _waiterSendOrderButton;
    private Button? _waiterServeOrderButton;
    private Button? _waiterCreateBillButton;
    private Button? _waiterCloseBillButton;
    private readonly ComboBox _paymentMethod = new() { Width = 130, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Label _cartSummary = new() { AutoSize = true, Text = "Корзина пуста", Font = new Font("Segoe UI", 10, FontStyle.Bold), Padding = new Padding(8, 8, 0, 8) };

    private readonly TextBox _lastName = new() { PlaceholderText = "Фамилия", Width = 140 };
    private readonly TextBox _firstName = new() { PlaceholderText = "Имя", Width = 140 };
    private readonly TextBox _phone = new() { PlaceholderText = "Телефон", Width = 140 };
    private readonly TextBox _tableNumbers = new() { PlaceholderText = "Номер столика", Text = "1", Width = 110 };
    private readonly DateTimePicker _start = new() { Width = 150, Format = DateTimePickerFormat.Custom, CustomFormat = "dd.MM.yyyy HH:mm", Value = DateTime.Today.AddHours(12) };
    private readonly DateTimePicker _end = new() { Width = 150, Format = DateTimePickerFormat.Custom, CustomFormat = "dd.MM.yyyy HH:mm", Value = DateTime.Today.AddHours(14) };
    private readonly NumericUpDown _resGuests = new() { Minimum = 1, Maximum = 50, Value = 2, Width = 60 };
    private readonly TextBox _stopReason = new() { PlaceholderText = "Причина стоп-листа", Width = 220 };

    // Поля администратора: новые сотрудники и график смен.
    private readonly ComboBox _adminEmployeeRole = new() { Width = 150, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox _adminEmployeeLogin = new() { PlaceholderText = "Логин", Width = 125 };
    private readonly TextBox _adminEmployeePassword = new() { PlaceholderText = "Пароль (от 6 символов)", Width = 165, UseSystemPasswordChar = true };
    private readonly TextBox _adminEmployeeLastName = new() { PlaceholderText = "Фамилия", Width = 130 };
    private readonly TextBox _adminEmployeeFirstName = new() { PlaceholderText = "Имя", Width = 125 };
    private readonly TextBox _adminEmployeePhone = new() { PlaceholderText = "Телефон", Width = 135 };
    private readonly ComboBox _adminShiftWaiter = new() { Width = 240, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly DateTimePicker _adminShiftStart = new() { Width = 160, Format = DateTimePickerFormat.Custom, CustomFormat = "dd.MM.yyyy HH:mm", Value = DateTime.Today.AddHours(9) };
    private readonly DateTimePicker _adminShiftEnd = new() { Width = 160, Format = DateTimePickerFormat.Custom, CustomFormat = "dd.MM.yyyy HH:mm", Value = DateTime.Today.AddHours(23) };
    private readonly CheckedListBox _adminShiftTables = new() { Width = 320, Height = 118, CheckOnClick = true, IntegralHeight = false, BorderStyle = BorderStyle.FixedSingle };
    private readonly DateTimePicker _adminShiftFilterDate = new()
    {
        Width = 135,
        Format = DateTimePickerFormat.Short,
        ShowCheckBox = true,
        Checked = false,
        Value = DateTime.Today
    };
    private readonly ComboBox _adminShiftFilterWaiter = new() { Width = 220, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _adminShiftFilterStatus = new() { Width = 150, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _adminShiftFilterType = new() { Width = 160, DropDownStyle = ComboBoxStyle.DropDownList };

    // Поля администратора: отчёт по продажам и пополнение склада.
    private readonly DateTimePicker _adminSalesFrom = new()
    {
        Width = 125,
        Format = DateTimePickerFormat.Short,
        Value = DateTime.Today.AddDays(-29)
    };
    private readonly DateTimePicker _adminSalesTo = new()
    {
        Width = 125,
        Format = DateTimePickerFormat.Short,
        Value = DateTime.Today
    };
    private readonly Label _adminSalesSummary = new()
    {
        AutoSize = true,
        Text = "Выберите период и сформируйте отчёт.",
        ForeColor = Color.DimGray,
        Padding = new Padding(5, 10, 0, 0)
    };
    private readonly NumericUpDown _adminRestockQuantity = new()
    {
        Minimum = 1,
        Maximum = 10000,
        Value = 1,
        Width = 90
    };
    private readonly TextBox _adminRestockComment = new()
    {
        PlaceholderText = "Комментарий к пополнению (необязательно)",
        Width = 250
    };

    private DataTable? _waiterMenuData;
    private DataTable? _clientMenuData;
    private int? _waiterOrderId;
    private int? _clientOrderId;

    public MainForm(UserSession user)
    {
        _user = user;
        Text = $"White Rabbit — {_user.RoleName}";
        StartPosition = FormStartPosition.CenterScreen;
        WindowState = FormWindowState.Maximized;
        MinimumSize = new Size(1100, 700);
        BackColor = Surface;

        var tabs = new TabControl
        {
            Dock = DockStyle.Fill,
            Font = new Font("Segoe UI", 10, FontStyle.Regular),
            Padding = new Point(16, 8)
        };

        if (_user.IsAdmin)
        {
            tabs.TabPages.Add(CreateTablesPage());
            tabs.TabPages.Add(CreateReservationsPage());
            tabs.TabPages.Add(CreateAdministrationPage());
            tabs.TabPages.Add(CreateKitchenPage());
        }
        else if (_user.IsClient)
        {
            tabs.TabPages.Add(CreateClientPage());
            tabs.TabPages.Add(CreateClientOrderStatusPage());
            tabs.TabPages.Add(CreateReservationsPage());
        }
        else if (_user.IsWaiter)
        {
            // Схема назначенных столиков встроена прямо в рабочее место официанта.
            tabs.TabPages.Add(CreateWaiterPage());
        }
        else if (_user.IsKitchen)
        {
            tabs.TabPages.Add(CreateKitchenPage());
        }

        if (_user.IsAdmin)
        {
            _adminEmployeeRole.Items.AddRange(new object[]
            {
                new RoleOption("WAITER", "Официант"),
                new RoleOption("KITCHEN", "Сотрудник кухни")
            });
            SetComboBoxSelection(_adminEmployeeRole, 0);
            _adminShiftFilterStatus.Items.AddRange(new object[]
            {
                new FilterOption("ALL", "Все статусы"),
                new FilterOption("PLANNED", "Запланирована"),
                new FilterOption("OPEN", "Открыта"),
                new FilterOption("CLOSED", "Закрыта")
            });
            SetComboBoxSelection(_adminShiftFilterStatus, 0);
            _adminShiftFilterType.Items.AddRange(new object[]
            {
                new FilterOption("ALL", "Все типы"),
                new FilterOption("SCHEDULED", "По графику"),
                new FilterOption("WALKIN", "Самостоятельная")
            });
            SetComboBoxSelection(_adminShiftFilterType, 0);
        }

        if (_user.IsWaiter)
        {
            _paymentMethod.Items.AddRange(new object[] { "Карта", "Наличные" });
            SetComboBoxSelection(_paymentMethod, 0);
            _paymentMethod.Enabled = false;
        }

        Controls.Add(tabs);
        Controls.Add(CreateHeader());

        _autoCloseTimer.Tick += async (_, _) => await RunSafeAsync(AutoCloseExpiredShiftsAsync);
        _autoCloseTimer.Start();
        FormClosed += (_, _) => _autoCloseTimer.Stop();

        _waiterSearch.TextChanged += (_, _) => RenderDishCards(_waiterCards, _waiterMenuData, _waiterSearch.Text, AddDishFromWaiterCardAsync);
        _clientSearch.TextChanged += (_, _) => RenderDishCards(_clientCards, _clientMenuData, _clientSearch.Text, AddDishFromClientCardAsync);
        _waiterTable.SelectedIndexChanged += (_, _) => ApplyGuestCapacity(_waiterTable, _waiterGuests);
        _clientTable.SelectedIndexChanged += (_, _) => ApplyGuestCapacity(_clientTable, _clientGuests);
        _start.ValueChanged += async (_, _) => await RunSafeAsync(LoadReservationTableMapAsync);
        _end.ValueChanged += async (_, _) => await RunSafeAsync(LoadReservationTableMapAsync);
        _resGuests.ValueChanged += async (_, _) => await RunSafeAsync(LoadReservationTableMapAsync);
        _reservationDay.ValueChanged += async (_, _) =>
        {
            if (_user.IsAdmin)
            {
                await RunSafeAsync(async () =>
                {
                    await LoadAdminReservationTableMapAsync();
                    if (_selectedAdminReservationTableId is int tableId)
                        await LoadReservationsForSelectedTableAsync(tableId);
                });
            }
        };
        _waiterReservationDay.ValueChanged += async (_, _) =>
        {
            if (_user.IsWaiter)
            {
                await RunSafeAsync(async () =>
                {
                    await LoadWaiterTablesAsync();
                    if (_selectedWaiterReservationTableId is int tableId)
                        await LoadWaiterReservationsForSelectedTableAsync(tableId);
                });
            }
        };
        _waiterOrdersGrid.SelectionChanged += async (_, _) => await RunSafeAsync(LoadWaiterItemsAsync);
        Shown += async (_, _) => await RunSafeAsync(RefreshAllAsync);
    }

    private Control CreateHeader()
    {
        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 70,
            BackColor = Color.White,
            Padding = new Padding(24, 0, 24, 0)
        };

        var title = new Label
        {
            Text = "WHITE RABBIT",
            Font = new Font("Segoe UI", 20, FontStyle.Bold),
            ForeColor = Ink,
            AutoSize = true,
            Location = new Point(24, 18)
        };
        var subtitle = new Label
        {
            Text = _user.RoleName,
            Font = new Font("Segoe UI", 10, FontStyle.Regular),
            ForeColor = Color.DimGray,
            AutoSize = true,
            Location = new Point(252, 28)
        };
        var name = new Label
        {
            Text = _user.FullName,
            Font = new Font("Segoe UI", 10, FontStyle.Regular),
            ForeColor = Color.DimGray,
            AutoSize = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        var exit = CreateButton("Выйти", secondary: true);
        exit.Width = 90;
        exit.Height = 34;
        exit.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        exit.Click += (_, _) => Close();

        header.Resize += (_, _) =>
        {
            exit.Location = new Point(header.Width - exit.Width - 24, 18);
            name.Location = new Point(Math.Max(330, exit.Left - name.Width - 18), 27);
        };
        header.Controls.AddRange(new Control[] { title, subtitle, name, exit });
        return header;
    }

    private TabPage CreateTablesPage()
    {
        var page = NewPage("Столики");
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(LoadTablesAsync);

        page.Controls.Add(CreateGridPanel(
            _adminTableOrderGrid,
            "Заказ выбранного столика",
            "Нажмите карточку занятого столика: здесь отобразится его незавершённый заказ.",
            _adminTableOrderHint));
        page.Controls.Add(CreateTableMapHost(
            _adminTableMap,
            _adminTableMapHint,
            "Столики ресторана",
            "Зелёный — свободен, жёлтый — забронирован, красный — занят заказом. Нажмите карточку, чтобы увидеть заказ.",
            318));
        page.Controls.Add(CreateToolbar(
            "Схема столиков",
            "Столики отображаются карточками вместо таблицы. Состояние обновляется после брони, заказа и оплаты.",
            refresh));
        return page;
    }

    private TabPage CreateReservationsPage()
    {
        var page = NewPage("Бронирование");
        var reserve = CreateButton("Забронировать");
        reserve.Click += async (_, _) => await RunSafeAsync(CreateReservationAsync);
        var cancel = CreateButton("Отменить бронь", secondary: true);
        cancel.Click += async (_, _) => await RunSafeAsync(CancelReservationAsync);
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(async () =>
        {
            await LoadReservationsAsync();
            await LoadReservationTableMapAsync();
            if (_user.IsAdmin) await LoadAdminReservationTableMapAsync();
        });

        var form = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 102,
            Padding = new Padding(20, 10, 20, 10),
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            AutoScroll = true,
            BackColor = Color.White
        };
        form.Controls.AddRange(new Control[]
        {
            Field("Фамилия", _lastName), Field("Имя", _firstName), Field("Телефон", _phone),
            Field("Столик", _tableNumbers), Field("Гостей", _resGuests),
            Field("Начало", _start), Field("Конец", _end), reserve, cancel, refresh
        });

        page.Controls.Add(_reservationsGrid);

        if (_user.IsClient)
            page.Controls.Add(CreateReservationTableMapPanel());
        else if (_user.IsAdmin)
            page.Controls.Add(CreateAdminReservationTableMapPanel());

        page.Controls.Add(form);
        page.Controls.Add(CreateSectionTitle(
            "Бронирование",
            _user.IsClient
                ? "Выберите дату, время и гостей, затем нажмите свободный столик на схеме. В списке показываются только ваши брони."
                : "Выберите дату и нажмите столик на схеме: внизу отобразятся все его брони за этот день."));
        return page;
    }

    private Control CreateReservationTableMapPanel()
    {
        var panel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 204,
            BackColor = Color.White,
            Padding = new Padding(16, 4, 16, 8)
        };

        var title = new Label
        {
            Text = "Схема столиков для бронирования",
            AutoSize = true,
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Ink,
            Location = new Point(20, 8)
        };

        _reservationTableMap.Dock = DockStyle.Fill;
        _reservationTableMap.Padding = new Padding(20, 34, 20, 8);
        panel.Controls.Add(_reservationTableMap);
        panel.Controls.Add(_reservationTableMapHint);
        panel.Controls.Add(title);
        return panel;
    }

    private Control CreateAdminReservationTableMapPanel()
    {
        var panel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 250,
            BackColor = Color.White,
            Padding = new Padding(16, 8, 16, 8)
        };

        var refresh = CreateButton("Показать брони", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(LoadAdminReservationTableMapAsync);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 52,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(4, 0, 4, 0)
        };
        toolbar.Controls.AddRange(new Control[]
        {
            Field("Дата", _reservationDay),
            refresh
        });

        var title = new Label
        {
            Text = "Брони по столикам",
            AutoSize = true,
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Ink,
            Dock = DockStyle.Top,
            Height = 25,
            Padding = new Padding(4, 2, 0, 0)
        };

        _adminReservationTableMap.Dock = DockStyle.Fill;
        panel.Controls.Add(_adminReservationTableMap);
        panel.Controls.Add(_adminReservationMapHint);
        panel.Controls.Add(toolbar);
        panel.Controls.Add(title);
        return panel;
    }

    private TabPage CreateWaiterPage()
    {
        var page = NewPage("Рабочее место официанта");

        var openShift = CreateButton("Открыть смену / прийти на смену", secondary: true);
        openShift.Click += async (_, _) => await RunSafeAsync(OpenShiftAsync);
        var closeShift = CreateButton("Закрыть смену", secondary: true);
        closeShift.Click += async (_, _) => await RunSafeAsync(CloseShiftAsync);
        var refreshWaiterTables = CreateButton("Обновить столики", secondary: true);
        refreshWaiterTables.Click += async (_, _) => await RunSafeAsync(LoadWaiterTablesAsync);
        var showWaiterReservations = CreateButton("Показать брони", secondary: true);
        showWaiterReservations.Click += async (_, _) => await RunSafeAsync(async () =>
        {
            await LoadWaiterTablesAsync();
            if (_selectedWaiterReservationTableId is int tableId)
                await LoadWaiterReservationsForSelectedTableAsync(tableId);
        });

        _waiterCreateOrderButton = CreateButton("Создать заказ");
        _waiterCreateOrderButton.Click += async (_, _) => await RunSafeAsync(CreateWaiterOrderAsync);
        _waiterCreateOrderButton.Enabled = false;

        _waiterSendOrderButton = CreateButton("Отправить на кухню");
        _waiterSendOrderButton.Click += async (_, _) => await RunSafeAsync(FinalizeWaiterAsync);
        _waiterSendOrderButton.Enabled = false;

        _waiterServeOrderButton = CreateButton("Принести заказ", secondary: true);
        _waiterServeOrderButton.Click += async (_, _) => await RunSafeAsync(ServeSelectedOrderAsync);
        _waiterServeOrderButton.Enabled = false;

        _waiterCreateBillButton = CreateButton("Пробить счёт", secondary: true);
        _waiterCreateBillButton.Click += async (_, _) => await RunSafeAsync(CreateBillForSelectedOrderAsync);
        _waiterCreateBillButton.Enabled = false;

        _waiterCloseBillButton = CreateButton("Закрыть счёт");
        _waiterCloseBillButton.Click += async (_, _) => await RunSafeAsync(CloseBillForSelectedOrderAsync);
        _waiterCloseBillButton.Enabled = false;

        var shiftHint = new Label
        {
            Text = "Смена может быть назначена администратором или открыта вами по приходу. Столики распределяются автоматически между открытыми сменами.",
            AutoSize = true,
            ForeColor = Color.DimGray,
            Padding = new Padding(5, 12, 0, 0)
        };

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 136,
            Padding = new Padding(20, 8, 20, 8),
            BackColor = Color.White,
            WrapContents = true,
            AutoScroll = true
        };
        toolbar.Controls.AddRange(new Control[]
        {
            openShift, closeShift, refreshWaiterTables,
            Field("Дата броней", _waiterReservationDay), showWaiterReservations,
            Field("Гостей", _waiterGuests),
            _waiterCreateOrderButton, _waiterSendOrderButton,
            _waiterServeOrderButton, _waiterCreateBillButton,
            Field("Оплата", _paymentMethod), _waiterCloseBillButton,
            _waiterOrderInfo, shiftHint
        });

        var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 670, BackColor = Surface };
        split.Panel1.Padding = new Padding(14, 14, 7, 14);
        split.Panel2.Padding = new Padding(7, 14, 14, 14);
        split.Panel1.Controls.Add(CreateMenuPanel("Меню", "Нажмите «Добавить» на карточке блюда.", _waiterSearch, _waiterCards));

        var rightTabs = new TabControl { Dock = DockStyle.Fill, Font = new Font("Segoe UI", 9) };
        var currentOrderTab = new TabPage("Текущий заказ") { BackColor = Color.White };
        currentOrderTab.Controls.Add(CreateGridPanel(
            _waiterItemsGrid,
            "Текущий заказ",
            "Выберите строку и удалите блюдо при необходимости.",
            CreateButton("Удалить блюдо", secondary: true, click: async (_, _) => await RunSafeAsync(RemoveFromWaiterAsync))));

        var activeOrdersTab = new TabPage("Мои активные заказы") { BackColor = Color.White };
        activeOrdersTab.Controls.Add(CreateGridPanel(
            _waiterOrdersGrid,
            "Мои активные заказы",
            "Выберите заказ: его статус подскажет доступное действие."));

        var reservationTab = new TabPage("Брони столика") { BackColor = Color.White };
        reservationTab.Controls.Add(CreateGridPanel(
            _waiterReservationsGrid,
            "Брони выбранного столика",
            "Выберите дату и нажмите карточку своего столика, чтобы увидеть все его брони за день."));

        rightTabs.TabPages.Add(currentOrderTab);
        rightTabs.TabPages.Add(activeOrdersTab);
        rightTabs.TabPages.Add(reservationTab);
        split.Panel2.Controls.Add(rightTabs);

        page.Controls.Add(split);
        page.Controls.Add(CreateTableMapHost(
            _waiterTableMap,
            _waiterTableMapHint,
            "Мои столики и брони",
            "Синяя карточка — столик назначен вам. Нажмите карточку: она выберется для заказа, а справа появятся брони на выбранную дату.",
            202));
        page.Controls.Add(toolbar);
        return page;
    }

    private TabPage CreateClientPage()
    {
        var page = NewPage("Заказать");

        var refreshTables = CreateButton("Обновить столики", secondary: true);
        refreshTables.Click += async (_, _) => await RunSafeAsync(LoadClientTablesAsync);
        var startOrder = CreateButton("Начать заказ");
        startOrder.Click += async (_, _) => await RunSafeAsync(CreateClientOrderAsync);
        var sendOrder = CreateButton("Отправить на кухню");
        sendOrder.Click += async (_, _) => await RunSafeAsync(FinalizeClientAsync);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 80,
            Padding = new Padding(20, 10, 20, 10),
            BackColor = Color.White,
            WrapContents = true,
            AutoScroll = true
        };
        toolbar.Controls.AddRange(new Control[]
        {
            Field("Столик", _clientTable), Field("Гостей", _clientGuests), refreshTables, startOrder, sendOrder, _clientOrderInfo
        });

        var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 760, BackColor = Surface };
        split.Panel1.Padding = new Padding(14, 14, 7, 14);
        split.Panel2.Padding = new Padding(7, 14, 14, 14);
        split.Panel1.Controls.Add(CreateMenuPanel("Меню White Rabbit", "Выберите блюдо — оно сразу добавится в корзину.", _clientSearch, _clientCards));

        var remove = CreateButton("Удалить выбранное", secondary: true);
        remove.Click += async (_, _) => await RunSafeAsync(RemoveFromClientAsync);
        split.Panel2.Controls.Add(CreateGridPanel(_clientCartGrid, "Корзина", "Проверьте заказ перед отправкой на кухню.", remove, _cartSummary));

        page.Controls.Add(split);
        page.Controls.Add(toolbar);
        return page;
    }

    private TabPage CreateClientOrderStatusPage()
    {
        var page = NewPage("Статус заказов");
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(LoadClientOrderStatusesAsync);
        page.Controls.Add(_clientOrderStatusesGrid);
        page.Controls.Add(CreateToolbar(
            "Мои заказы",
            "Здесь отображается текущий статус каждого вашего заказа и состояние счёта.",
            refresh));
        return page;
    }

    private TabPage CreateKitchenPage()
    {
        var page = NewPage("Кухня");
        var cooking = CreateButton("Готовится");
        cooking.Click += async (_, _) => await RunSafeAsync(() => UpdateKitchenStatusAsync("PREPARING"));
        var ready = CreateButton("Готово к выдаче");
        ready.Click += async (_, _) => await RunSafeAsync(() => UpdateKitchenStatusAsync("READY"));
        var accepted = CreateButton("Передано официанту");
        accepted.Click += async (_, _) => await RunSafeAsync(() => UpdateKitchenStatusAsync("ACCEPTED"));
        var stop = CreateButton("В стоп-лист", secondary: true);
        stop.Click += async (_, _) => await RunSafeAsync(() => SetStopListAsync(true));
        var restore = CreateButton("Вернуть в меню", secondary: true);
        restore.Click += async (_, _) => await RunSafeAsync(() => SetStopListAsync(false));
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(RefreshKitchenAsync);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 78,
            Padding = new Padding(20, 10, 20, 10),
            BackColor = Color.White,
            WrapContents = true,
            AutoScroll = true
        };
        toolbar.Controls.AddRange(new Control[] { cooking, ready, accepted, _stopReason, stop, restore, refresh });

        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, SplitterDistance = 300 };
        split.Panel1.Padding = new Padding(14, 14, 14, 7);
        split.Panel2.Padding = new Padding(14, 7, 14, 14);
        split.Panel1.Controls.Add(CreateGridPanel(_kitchenOrdersGrid, "Очередь заказов", "Заказы из приложения и от официантов."));
        split.Panel2.Controls.Add(CreateGridPanel(_kitchenDishesGrid, "Стоп-лист", "Выберите блюдо и измените его доступность."));
        page.Controls.Add(split);
        page.Controls.Add(toolbar);
        return page;
    }

    private TabPage CreateAdministrationPage()
    {
        var page = NewPage("Администрирование");
        var tabs = new TabControl { Dock = DockStyle.Fill, Font = new Font("Segoe UI", 10) };
        tabs.TabPages.Add(CreateEmployeesAdministrationPage());
        tabs.TabPages.Add(CreateShiftAdministrationPage());
        tabs.TabPages.Add(CreateOrderStatusAdministrationPage());
        tabs.TabPages.Add(CreateSalesReportAdministrationPage());
        tabs.TabPages.Add(CreateStockAdministrationPage());
        page.Controls.Add(tabs);
        return page;
    }

    private TabPage CreateEmployeesAdministrationPage()
    {
        var page = NewPage("Сотрудники");
        var addEmployee = CreateButton("Добавить сотрудника");
        addEmployee.Click += async (_, _) => await RunSafeAsync(AddEmployeeAsync);
        var deleteEmployee = CreateButton("Удалить выбранного", secondary: true);
        deleteEmployee.Click += async (_, _) => await RunSafeAsync(ArchiveSelectedEmployeeAsync);
        var refresh = CreateButton("Обновить список", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(RefreshAdministrationAsync);

        var form = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 118,
            Padding = new Padding(20, 10, 20, 10),
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            AutoScroll = true,
            BackColor = Color.White
        };
        form.Controls.AddRange(new Control[]
        {
            Field("Роль", _adminEmployeeRole),
            Field("Логин", _adminEmployeeLogin),
            Field("Пароль", _adminEmployeePassword),
            Field("Фамилия", _adminEmployeeLastName),
            Field("Имя", _adminEmployeeFirstName),
            Field("Телефон", _adminEmployeePhone),
            addEmployee, deleteEmployee, refresh
        });

        page.Controls.Add(_adminEmployeesGrid);
        page.Controls.Add(form);
        page.Controls.Add(CreateSectionTitle(
            "Сотрудники",
            "Администратор создаёт учётные записи официантов и сотрудников кухни."));
        return page;
    }

    private TabPage CreateShiftAdministrationPage()
    {
        var page = NewPage("Смены и столики");
        var saveShift = CreateButton("Запланировать смену");
        saveShift.Click += async (_, _) => await RunSafeAsync(CreateAdminShiftAsync);
        var openShift = CreateButton("Открыть выбранную смену", secondary: true);
        openShift.Click += async (_, _) => await RunSafeAsync(OpenAdminShiftAsync);
        var closeShift = CreateButton("Закрыть выбранную смену", secondary: true);
        closeShift.Click += async (_, _) => await RunSafeAsync(CloseAdminShiftAsync);
        var distributeTables = CreateButton("Распределить столики", secondary: true);
        distributeTables.Click += async (_, _) => await RunSafeAsync(RebalanceOpenWaiterTablesAsync);
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(RefreshAdministrationAsync);
        var applyFilters = CreateButton("Применить фильтры", secondary: true);
        applyFilters.Click += async (_, _) => await RunSafeAsync(LoadAdminShiftsAsync);
        var resetFilters = CreateButton("Сбросить", secondary: true);
        resetFilters.Click += async (_, _) => await RunSafeAsync(async () =>
        {
            _adminShiftFilterDate.Checked = false;
            SetComboBoxSelection(_adminShiftFilterWaiter, 0);
            SetComboBoxSelection(_adminShiftFilterStatus, 0);
            SetComboBoxSelection(_adminShiftFilterType, 0);
            await LoadAdminShiftsAsync();
        });

        var settings = new Panel
        {
            Dock = DockStyle.Top,
            Height = 202,
            Padding = new Padding(20, 8, 20, 8),
            BackColor = Color.White
        };

        var dataFields = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 72,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            AutoScroll = true
        };
        dataFields.Controls.AddRange(new Control[]
        {
            Field("Официант", _adminShiftWaiter),
            Field("Начало смены", _adminShiftStart),
            Field("Конец смены", _adminShiftEnd),
            saveShift,
            openShift,
            closeShift,
            distributeTables,
            refresh
        });

        var filters = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 76,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            AutoScroll = true,
            Padding = new Padding(0, 4, 0, 0)
        };
        filters.Controls.AddRange(new Control[]
        {
            Field("Дата", _adminShiftFilterDate),
            Field("Официант", _adminShiftFilterWaiter),
            Field("Статус", _adminShiftFilterStatus),
            Field("Тип смены", _adminShiftFilterType),
            applyFilters,
            resetFilters
        });

        var hint = new Label
        {
            Text = "Фильтры позволяют выбрать смены по дате, официанту, статусу и типу. Столики автоматически распределяются между открытыми сменами.",
            Dock = DockStyle.Bottom,
            Height = 28,
            AutoEllipsis = true,
            ForeColor = Color.DimGray,
            Padding = new Padding(4, 6, 4, 0)
        };

        settings.Controls.Add(filters);
        settings.Controls.Add(dataFields);
        settings.Controls.Add(hint);
        page.Controls.Add(_adminShiftsGrid);
        page.Controls.Add(settings);
        page.Controls.Add(CreateSectionTitle(
            "График смен и автоматическое распределение столиков",
            "Администратор видит смены по графику и самостоятельные смены официантов."));
        return page;
    }

    private TabPage CreateOrderStatusAdministrationPage()
    {
        var page = NewPage("Статусы заказов");
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(LoadAdminOrderStatusesAsync);
        page.Controls.Add(_adminOrderStatusesGrid);
        page.Controls.Add(CreateToolbar(
            "Статусы заказов",
            "Все заказы ресторана: источник, текущий статус, счёт и время оплаты.",
            refresh));
        return page;
    }

    private TabPage CreateSalesReportAdministrationPage()
    {
        var page = NewPage("Отчёт по продажам");
        var buildReport = CreateButton("Сформировать отчёт");
        buildReport.Click += async (_, _) => await RunSafeAsync(LoadAdminSalesReportAsync);
        var refresh = CreateButton("Обновить", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(LoadAdminSalesReportAsync);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 82,
            Padding = new Padding(20, 10, 20, 10),
            BackColor = Color.White,
            WrapContents = true,
            AutoScroll = true
        };
        toolbar.Controls.AddRange(new Control[]
        {
            Field("Дата с", _adminSalesFrom),
            Field("Дата по", _adminSalesTo),
            buildReport,
            refresh,
            _adminSalesSummary
        });

        page.Controls.Add(_adminSalesGrid);
        page.Controls.Add(toolbar);
        page.Controls.Add(CreateSectionTitle(
            "Отчёт по продажам",
            "В отчёт попадают только заказы с закрытым и оплаченным счётом."));
        return page;
    }

    private TabPage CreateStockAdministrationPage()
    {
        var page = NewPage("Склад");
        var restock = CreateButton("Пополнить выбранное блюдо");
        restock.Click += async (_, _) => await RunSafeAsync(RestockSelectedDishAsync);
        var refresh = CreateButton("Обновить остатки", secondary: true);
        refresh.Click += async (_, _) => await RunSafeAsync(LoadAdminStockAsync);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 82,
            Padding = new Padding(20, 10, 20, 10),
            BackColor = Color.White,
            WrapContents = true,
            AutoScroll = true
        };
        toolbar.Controls.AddRange(new Control[]
        {
            Field("Добавить порций", _adminRestockQuantity),
            Field("Комментарий", _adminRestockComment),
            restock,
            refresh
        });

        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Horizontal,
            SplitterDistance = 315,
            BackColor = Surface
        };
        split.Panel1.Padding = new Padding(14, 14, 14, 7);
        split.Panel2.Padding = new Padding(14, 7, 14, 14);
        split.Panel1.Controls.Add(CreateGridPanel(
            _adminStockGrid,
            "Остатки блюд",
            "Выберите блюдо и укажите число порций для пополнения."));
        split.Panel2.Controls.Add(CreateGridPanel(
            _adminStockHistoryGrid,
            "История пополнений",
            "Последние 100 операций пополнения склада."));

        page.Controls.Add(split);
        page.Controls.Add(toolbar);
        page.Controls.Add(CreateSectionTitle(
            "Склад",
            "Пополнение увеличивает доступное количество порций в меню и сохраняется в истории."));
        return page;
    }

    private static TabPage NewPage(string title) => new(title) { BackColor = Surface, Padding = new Padding(0) };

    private static Panel CreateSectionTitle(string title, string hint)
    {
        var panel = new Panel { Dock = DockStyle.Top, Height = 62, BackColor = Surface, Padding = new Padding(20, 10, 20, 0) };
        panel.Controls.Add(new Label { Text = title, AutoSize = true, Font = new Font("Segoe UI", 15, FontStyle.Bold), ForeColor = Ink, Location = new Point(20, 8) });
        panel.Controls.Add(new Label { Text = hint, AutoSize = true, Font = new Font("Segoe UI", 9), ForeColor = Color.DimGray, Location = new Point(20, 34) });
        return panel;
    }

    private static Panel CreateToolbar(string title, string hint, params Control[] actions)
    {
        var panel = new Panel { Dock = DockStyle.Top, Height = 80, BackColor = Color.White };
        var heading = new Label { Text = title, AutoSize = true, Font = new Font("Segoe UI", 15, FontStyle.Bold), ForeColor = Ink, Location = new Point(20, 9) };
        var description = new Label { Text = hint, AutoSize = true, Font = new Font("Segoe UI", 9), ForeColor = Color.DimGray, Location = new Point(20, 36) };
        var actionPanel = new FlowLayoutPanel { Dock = DockStyle.Right, Width = 500, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(10, 21, 18, 0), WrapContents = false, AutoScroll = true };
        actionPanel.Controls.AddRange(actions);
        panel.Controls.AddRange(new Control[] { heading, description, actionPanel });
        return panel;
    }

    private static FlowLayoutPanel CreateCardsPanel() => new()
    {
        Dock = DockStyle.Fill,
        AutoScroll = true,
        BackColor = Surface,
        Padding = new Padding(4),
        FlowDirection = FlowDirection.LeftToRight,
        WrapContents = true
    };

    private static FlowLayoutPanel CreateTableMapPanel() => new()
    {
        Dock = DockStyle.Fill,
        AutoScroll = true,
        BackColor = Color.White,
        Padding = new Padding(12, 8, 12, 8),
        FlowDirection = FlowDirection.LeftToRight,
        WrapContents = true
    };

    private static Panel CreateTableMapHost(FlowLayoutPanel map, Label hint, string title, string description, int height = 0)
    {
        var panel = new Panel
        {
            Dock = height > 0 ? DockStyle.Top : DockStyle.Fill,
            Height = height > 0 ? height : 0,
            BackColor = Color.White,
            Padding = new Padding(14, 6, 14, 6)
        };
        var titleLabel = new Label
        {
            Text = title,
            Dock = DockStyle.Top,
            Height = 24,
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Ink,
            Padding = new Padding(4, 1, 0, 0)
        };
        var descriptionLabel = new Label
        {
            Text = description,
            Dock = DockStyle.Top,
            Height = 21,
            ForeColor = Color.DimGray,
            Font = new Font("Segoe UI", 8),
            Padding = new Padding(4, 0, 0, 0)
        };
        map.Dock = DockStyle.Fill;
        panel.Controls.Add(map);
        panel.Controls.Add(hint);
        panel.Controls.Add(descriptionLabel);
        panel.Controls.Add(titleLabel);
        return panel;
    }

    private static Control CreateMenuPanel(string title, string hint, TextBox search, FlowLayoutPanel cards)
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = Surface };
        var filter = new Panel { Dock = DockStyle.Top, Height = 56, BackColor = Color.White, Padding = new Padding(12, 10, 12, 10) };
        var label = new Label { Text = "Поиск", AutoSize = true, Location = new Point(14, 18), ForeColor = Color.DimGray };
        search.Location = new Point(70, 12);
        filter.Controls.AddRange(new Control[] { label, search });
        panel.Controls.Add(cards);
        panel.Controls.Add(filter);
        panel.Controls.Add(CreateSectionTitle(title, hint));
        return panel;
    }

    private static Control CreateGridPanel(DataGridView grid, string title, string hint, params Control[] footerControls)
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };
        var header = CreateSectionTitle(title, hint);
        header.BackColor = Color.White;
        panel.Controls.Add(grid);
        panel.Controls.Add(header);

        if (footerControls.Length > 0)
        {
            var footer = new FlowLayoutPanel
            {
                Dock = DockStyle.Bottom,
                Height = 56,
                Padding = new Padding(8, 9, 8, 8),
                BackColor = Color.White,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false
            };
            footer.Controls.AddRange(footerControls);
            panel.Controls.Add(footer);
            grid.Dock = DockStyle.Fill;
        }

        return panel;
    }

    private static Button CreateButton(string text, bool secondary = false, EventHandler? click = null)
    {
        var button = new Button
        {
            Text = text,
            AutoSize = true,
            MinimumSize = new Size(110, 36),
            Margin = new Padding(5, 8, 5, 8),
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            Cursor = Cursors.Hand,
            BackColor = secondary ? Color.White : Accent,
            ForeColor = secondary ? Ink : Color.White
        };
        button.FlatAppearance.BorderColor = secondary ? Color.Silver : Accent;
        button.FlatAppearance.BorderSize = 1;
        if (click is not null) button.Click += click;
        return button;
    }

    private static FlowLayoutPanel Field(string labelText, Control control)
    {
        var field = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            Margin = new Padding(5, 0, 5, 0)
        };
        field.Controls.Add(new Label { Text = labelText, AutoSize = true, ForeColor = Color.DimGray });
        field.Controls.Add(control);
        return field;
    }

    private static DataGridView CreateGrid()
    {
        var grid = new DataGridView
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            AllowUserToResizeRows = false,
            RowHeadersVisible = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            BackgroundColor = Color.White,
            BorderStyle = BorderStyle.None,
            EnableHeadersVisualStyles = false,
            ColumnHeadersHeight = 38,
            RowTemplate = { Height = 36 },
            DefaultCellStyle = new DataGridViewCellStyle
            {
                Font = new Font("Segoe UI", 10),
                Padding = new Padding(6, 3, 6, 3),
                SelectionBackColor = Color.FromArgb(245, 230, 231),
                SelectionForeColor = Ink
            },
            ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle
            {
                Font = new Font("Segoe UI", 10, FontStyle.Bold),
                BackColor = Color.FromArgb(244, 242, 240),
                ForeColor = Ink,
                Padding = new Padding(6, 4, 6, 4)
            }
        };
        grid.DataBindingComplete += (_, _) => HideTechnicalColumns(grid);
        return grid;
    }

    private static void HideTechnicalColumns(DataGridView grid)
    {
        // При повторной загрузке DataGridView первая колонка часто является техническим ID.
        // Нельзя скрывать колонку, в ячейке которой сейчас стоит курсор: WinForms выбрасывает
        // исключение «Текущую ячейку нельзя сделать невидимой».
        var technicalColumns = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "DishId", "OrderId", "ReservationId", "TableId", "UserId", "VisitId",
            "WaiterId", "ShiftId", "WaiterUserId", "StatusCode", "BillIssued", "BillPaid",
            "StockMovementId", "AdminUserId", "ClosedByUserId"
        };

        if (grid.Columns.Count == 0)
            return;

        var firstVisibleColumn = grid.Columns
            .Cast<DataGridViewColumn>()
            .FirstOrDefault(column => !technicalColumns.Contains(column.Name));

        // Сначала переносим курсор на обычную видимую колонку, затем скрываем служебные поля.
        if (firstVisibleColumn is not null && grid.Rows.Count > 0)
        {
            var rowIndex = grid.CurrentCell?.RowIndex ?? 0;
            if (rowIndex < 0 || rowIndex >= grid.Rows.Count)
                rowIndex = 0;

            var currentColumn = grid.CurrentCell?.OwningColumn;
            if (currentColumn is not null && technicalColumns.Contains(currentColumn.Name))
                grid.CurrentCell = grid.Rows[rowIndex].Cells[firstVisibleColumn.Index];
        }

        foreach (var name in technicalColumns)
        {
            if (grid.Columns.Contains(name))
                grid.Columns[name].Visible = false;
        }
    }

    // Скрывает закрытые для текущего рабочего списка записи, не удаляя их из БД.
    // Это позволяет сохранить историю заказов и броней для отчётов.
    private static DataTable HideRowsWithStatus(DataTable source, string statusToHide)
    {
        if (!source.Columns.Contains("Статус"))
        {
            return source;
        }

        var escapedStatus = statusToHide.Replace("'", "''");
        var view = new DataView(source)
        {
            RowFilter = $"[Статус] <> '{escapedStatus}'"
        };

        return view.ToTable();
    }

    private async Task RefreshAllAsync()
    {
        await AutoCloseExpiredShiftsAsync();
        if (_user.IsAdmin || _user.IsWaiter) await LoadTablesAsync();
        if (_user.IsAdmin || _user.IsClient) await LoadReservationsAsync();
        if (_user.IsAdmin) await LoadAdminReservationTableMapAsync();
        if (_user.IsWaiter) await RefreshWaiterAsync();
        if (_user.IsClient) await RefreshClientAsync();
        if (_user.IsAdmin || _user.IsKitchen) await RefreshKitchenAsync();
        if (_user.IsAdmin) await RefreshAdministrationAsync();
    }

    private async Task LoadTablesAsync()
    {
        var tables = await Database.QueryAsync("SELECT * FROM dbo.vw_TableScheme ORDER BY [№ столика]");
        _tablesGrid.DataSource = tables;
        if (_user.IsAdmin)
            RenderAdminTableMap(tables);
    }

    private async Task LoadReservationsAsync()
    {
        if (_user.IsAdmin && _selectedAdminReservationTableId is int selectedTableId)
        {
            await LoadReservationsForSelectedTableAsync(selectedTableId);
            return;
        }

        if (_user.IsClient)
        {
            // Клиент получает только свои брони. Проверка выполняется в SQL-процедуре,
            // поэтому чужие данные не выдаются даже при прямом вызове процедуры.
            _reservationsGrid.DataSource = await Database.ProcedureAsync(
                "dbo.sp_GetClientReservations",
                Database.P("@UserId", _user.UserId));
            return;
        }

        _reservationsGrid.DataSource = new DataTable();
    }

    private async Task LoadAdminReservationTableMapAsync()
    {
        if (!_user.IsAdmin || IsDisposed)
            return;

        var tables = await Database.ProcedureAsync(
            "dbo.sp_GetReservationDayTableMap",
            Database.P("@ReservationDate", _reservationDay.Value.Date));
        RenderAdminReservationTableMap(tables);
    }

    private async Task LoadReservationsForSelectedTableAsync(int tableId)
    {
        _reservationsGrid.DataSource = await Database.ProcedureAsync(
            "dbo.sp_GetReservationsByTableAndDate",
            Database.P("@ReservationDate", _reservationDay.Value.Date),
            Database.P("@TableId", tableId));
    }

    private void RenderAdminTableMap(DataTable tables)
    {
        _adminTableMap.SuspendLayout();
        _adminTableMap.Controls.Clear();

        foreach (DataRow row in tables.Rows)
        {
            if (!TryGetRowId(row, "TableId", out var tableId)) continue;
            var tableNumber = TryGetNumber(row, "№ столика", "TableNumber");
            var seats = TryGetNumber(row, "Мест", "SeatsCount");
            var zone = GetString(row, "Зона", "HallZone");
            var status = GetString(row, "Доступность", "AvailabilityNow", "CurrentStatus");
            var selected = _selectedAdminTableId == tableId;
            _adminTableMap.Controls.Add(CreateVisualTableButton(
                tableId,
                tableNumber,
                seats,
                zone,
                status,
                selected,
                async () =>
                {
                    _selectedAdminTableId = tableId;
                    await LoadAdminTableOrderAsync(tableNumber, status);
                    RenderAdminTableMap(tables);
                }));
        }

        _adminTableMapHint.Text = _adminTableMap.Controls.Count == 0
            ? "Столики не найдены."
            : "Зелёный — свободен, жёлтый — забронирован, красный — занят заказом. Нажмите карточку, чтобы увидеть заказ.";
        _adminTableMap.ResumeLayout();
    }

    private async Task LoadAdminTableOrderAsync(int tableNumber, string tableStatus)
    {
        // Используется уже существующая административная процедура, поэтому новое SQL-обновление не требуется.
        var allOrders = await Database.ProcedureAsync("dbo.sp_AdminGetOrderStatuses");
        var tableOrders = allOrders.Clone();

        foreach (DataRow row in allOrders.Rows)
        {
            var rowTableNumber = TryGetNumber(row, "№ столика", "TableNumber");
            var orderStatus = GetString(row, "Статус заказа", "Статус");
            if (rowTableNumber == tableNumber && !string.Equals(orderStatus, "Закрыт", StringComparison.OrdinalIgnoreCase))
                tableOrders.ImportRow(row);
        }

        _adminTableOrderGrid.DataSource = tableOrders;
        _adminTableOrderHint.Text = tableOrders.Rows.Count > 0
            ? $"Столик №{tableNumber}: показан текущий незавершённый заказ."
            : tableStatus.Contains("занят", StringComparison.OrdinalIgnoreCase)
                ? $"Столик №{tableNumber} отмечен как занятый, но активный заказ в базе не найден. Обновите схему столиков."
                : $"Столик №{tableNumber}: активного заказа нет.";
    }

    private void RenderAdminReservationTableMap(DataTable tables)
    {
        _adminReservationTableMap.SuspendLayout();
        _adminReservationTableMap.Controls.Clear();

        foreach (DataRow row in tables.Rows)
        {
            if (!TryGetRowId(row, "TableId", out var tableId)) continue;
            var tableNumber = TryGetNumber(row, "TableNumber", "№ столика");
            var seats = TryGetNumber(row, "SeatsCount", "Мест");
            var zone = GetString(row, "HallZone", "Зона");
            var reservationCount = TryGetNumber(row, "ReservationCount", "Количество броней");
            var status = GetString(row, "DayStatus", "Статус дня");
            if (string.IsNullOrWhiteSpace(status))
                status = reservationCount > 0 ? $"Броней: {reservationCount}" : "Свободен";
            else if (reservationCount > 0)
                status += $" · броней: {reservationCount}";

            var selected = _selectedAdminReservationTableId == tableId;
            var button = CreateVisualTableButton(
                tableId,
                tableNumber,
                seats,
                zone,
                status,
                selected,
                async () =>
                {
                    _selectedAdminReservationTableId = tableId;
                    _tableNumbers.Text = tableNumber.ToString();
                    _start.Value = _reservationDay.Value.Date.AddHours(12);
                    _end.Value = _reservationDay.Value.Date.AddHours(14);
                    _adminReservationMapHint.Text = $"Столик №{tableNumber}: показаны брони за {_reservationDay.Value:dd.MM.yyyy}.";
                    await LoadReservationsForSelectedTableAsync(tableId);
                    await LoadAdminReservationTableMapAsync();
                });
            _adminReservationTableMap.Controls.Add(button);
        }

        if (_selectedAdminReservationTableId is null)
            _adminReservationMapHint.Text = "Нажмите столик: ниже отобразятся все его брони за выбранный день.";
        _adminReservationTableMap.ResumeLayout();
    }

    private void RenderWaiterTableMap(DataTable tables)
    {
        _waiterTableMap.SuspendLayout();
        _waiterTableMap.Controls.Clear();

        foreach (DataRow row in tables.Rows)
        {
            if (!TryGetRowId(row, "TableId", out var tableId)) continue;
            var tableNumber = TryGetNumber(row, "TableNumber", "№ столика");
            var seats = TryGetNumber(row, "SeatsCount", "Мест");
            var zone = GetString(row, "HallZone", "Зона");
            var reservationCount = TryGetNumber(row, "ReservationCount", "Количество броней");
            var dayStatus = GetString(row, "DayStatus", "Статус");
            var selected = _selectedWaiterTableId == tableId || _selectedWaiterReservationTableId == tableId;
            var status = reservationCount > 0
                ? $"Назначен вам · броней: {reservationCount}"
                : "Назначен вам · броней нет";

            var button = CreateVisualTableButton(
                tableId,
                tableNumber,
                seats,
                zone,
                status,
                selected,
                async () =>
                {
                    _selectedWaiterTableId = tableId;
                    _selectedWaiterReservationTableId = tableId;
                    SelectTableInCombo(_waiterTable, tableId);
                    _waiterOrderInfo.Text = $"Выбран столик №{tableNumber}. Укажите число гостей и создайте заказ.";
                    _waiterTableMapHint.Text = $"Столик №{tableNumber}: {dayStatus}. Показаны брони за {_waiterReservationDay.Value:dd.MM.yyyy}.";
                    await LoadWaiterReservationsForSelectedTableAsync(tableId);
                    RenderWaiterTableMap(tables);
                });
            _waiterTableMap.Controls.Add(button);
        }

        if (_waiterTableMap.Controls.Count == 0)
            _waiterTableMapHint.Text = "Нет назначенных столиков. Откройте смену или обратитесь к администратору.";
        else if (_selectedWaiterReservationTableId is null)
            _waiterTableMapHint.Text = "Нажмите карточку своего столика: он выберется для заказа, а справа появятся его брони на выбранную дату.";

        _waiterTableMap.ResumeLayout();
    }

    private Button CreateVisualTableButton(
        int tableId,
        int tableNumber,
        int seats,
        string zone,
        string status,
        bool selected,
        Func<Task>? onClick)
    {
        var normalized = status.ToLowerInvariant();
        var isBusy = normalized.Contains("занят");
        var isReserved = normalized.Contains("брон") || normalized.Contains("забронир");
        var isAssigned = normalized.Contains("назначен");
        var baseColor = selected
            ? Accent
            : isBusy
                ? Color.FromArgb(252, 231, 231)
                : isReserved
                    ? Color.FromArgb(255, 247, 220)
                    : isAssigned
                        ? Color.FromArgb(229, 239, 255)
                        : Color.FromArgb(235, 247, 235);
        var borderColor = selected
            ? Accent
            : isBusy
                ? Color.FromArgb(201, 92, 92)
                : isReserved
                    ? Color.FromArgb(204, 156, 45)
                    : isAssigned
                        ? Color.FromArgb(73, 120, 180)
                        : Color.FromArgb(85, 142, 85);

        var button = new Button
        {
            Tag = tableId,
            Text = $"СТОЛ №{tableNumber}\n{seats} мест{(string.IsNullOrWhiteSpace(zone) ? string.Empty : $" · {zone}")}\n{status}",
            Width = 164,
            Height = 86,
            Margin = new Padding(7),
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            BackColor = baseColor,
            ForeColor = selected ? Color.White : Ink,
            TextAlign = ContentAlignment.MiddleCenter,
            Cursor = onClick is null ? Cursors.Default : Cursors.Hand,
            Enabled = true
        };
        button.FlatAppearance.BorderColor = borderColor;
        button.FlatAppearance.BorderSize = selected ? 2 : 1;
        if (onClick is not null)
            button.Click += async (_, _) => await RunSafeAsync(onClick);
        return button;
    }

    private static void SelectTableInCombo(ComboBox box, int tableId)
    {
        for (var index = 0; index < box.Items.Count; index++)
        {
            if (box.Items[index] is TableOption option && option.Id == tableId)
            {
                SetComboBoxSelection(box, index);
                return;
            }
        }
    }

    private async Task LoadReservationTableMapAsync()
    {
        if (!_user.IsClient || IsDisposed)
            return;

        if (_end.Value <= _start.Value)
        {
            _reservationTableMap.Controls.Clear();
            _reservationTableMapHint.Text = "Время окончания брони должно быть больше времени начала.";
            return;
        }

        var tables = await Database.ProcedureAsync(
            "dbo.sp_GetReservationTableMap",
            Database.P("@StartAt", _start.Value),
            Database.P("@EndAt", _end.Value),
            Database.P("@GuestCount", Convert.ToInt32(_resGuests.Value)));

        RenderReservationTableMap(tables);
    }

    private void RenderReservationTableMap(DataTable tables)
    {
        _reservationTableMap.SuspendLayout();
        _reservationTableMap.Controls.Clear();

        foreach (DataRow row in tables.Rows)
        {
            var tableNumber = Convert.ToString(row["TableNumber"]) ?? string.Empty;
            var seats = Convert.ToInt32(row["SeatsCount"]);
            var available = Convert.ToBoolean(row["IsAvailable"]);
            var selected = string.Equals(_tableNumbers.Text.Trim(), tableNumber, StringComparison.OrdinalIgnoreCase);
            var state = available ? "Свободен" : Convert.ToString(row["AvailabilityReason"]);

            var tableButton = new Button
            {
                Text = $"СТОЛ {tableNumber}{Environment.NewLine}{seats} мест{Environment.NewLine}{state}",
                Tag = tableNumber,
                Size = new Size(122, 74),
                Margin = new Padding(6),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 9, FontStyle.Bold),
                Cursor = available ? Cursors.Hand : Cursors.Default,
                Enabled = available,
                BackColor = selected ? Accent : available ? Color.FromArgb(239, 247, 239) : Color.FromArgb(244, 244, 244),
                ForeColor = selected ? Color.White : Ink
            };
            tableButton.FlatAppearance.BorderColor = selected ? Accent : available ? Color.FromArgb(92, 140, 92) : Color.Silver;
            tableButton.Click += async (_, _) => await RunSafeAsync(async () =>
            {
                _tableNumbers.Text = Convert.ToString(tableButton.Tag) ?? string.Empty;
                _reservationTableMapHint.Text = $"Выбран столик №{_tableNumbers.Text}. Нажмите «Забронировать».";
                await LoadReservationTableMapAsync();
            });
            _reservationTableMap.Controls.Add(tableButton);
        }

        _reservationTableMapHint.Text = _reservationTableMap.Controls.Count == 0
            ? "Нет доступных столиков для указанных условий."
            : "Свободный столик — зелёный. Недоступный — серый. Нажмите на свободный столик для выбора.";
        _reservationTableMap.ResumeLayout();
    }

    private async Task CreateReservationAsync()
    {
        RequireText(_lastName, "Введите фамилию.");
        RequireText(_firstName, "Введите имя.");
        RequireText(_tableNumbers, "Выберите столик на схеме или введите его номер.");
        var result = await Database.ProcedureAsync(
            "dbo.sp_CreateReservationSafe",
            Database.P("@UserId", _user.IsClient ? _user.UserId : null),
            Database.P("@LastName", _lastName.Text.Trim()),
            Database.P("@FirstName", _firstName.Text.Trim()),
            Database.P("@Phone", Empty(_phone.Text)),
            Database.P("@StartAt", _start.Value),
            Database.P("@EndAt", _end.Value),
            Database.P("@GuestCount", Convert.ToInt32(_resGuests.Value)),
            Database.P("@TableNumbers", _tableNumbers.Text.Trim()));
        ShowResult(result);
        await LoadReservationsAsync();
        await LoadReservationTableMapAsync();
        if (_user.IsAdmin)
        {
            await LoadTablesAsync();
            await LoadAdminReservationTableMapAsync();
        }
    }

    private async Task CancelReservationAsync()
    {
        if (!TryGetId(_reservationsGrid, "ReservationId", out var reservationId))
        {
            Info("Выберите бронь в списке.");
            return;
        }
        var result = await Database.ProcedureAsync(
            "dbo.sp_CancelReservation",
            Database.P("@ReservationId", reservationId),
            Database.P("@RequesterUserId", _user.UserId));
        ShowResult(result);
        await LoadReservationsAsync();
        await LoadReservationTableMapAsync();
        if (_user.IsAdmin)
        {
            await LoadTablesAsync();
            await LoadAdminReservationTableMapAsync();
        }
    }

    private async Task RefreshWaiterAsync()
    {
        if (_user.IsWaiter) await LoadWaiterTablesAsync();
        await LoadWaiterMenuAsync();
        await LoadWaiterOrdersAsync();
    }

    private async Task OpenShiftAsync()
    {
        var result = await Database.ProcedureAsync("dbo.sp_OpenCurrentWaiterShift", Database.P("@UserId", _user.UserId));
        ShowResult(result);
        await RefreshWaiterAsync();
    }

    private async Task CloseShiftAsync()
    {
        var reason = ReasonDialog.Ask(
            this,
            "Закрытие смены",
            "Если смена закрывается раньше назначенного времени, укажите причину. После окончания времени поле можно оставить пустым.");
        if (reason is null) return;

        var result = await Database.ProcedureAsync(
            "dbo.sp_CloseCurrentWaiterShift",
            Database.P("@UserId", _user.UserId),
            Database.P("@Reason", Empty(reason)));
        ShowResult(result);
        _waiterTable.DataSource = null;
        _waiterTable.Enabled = false;
        _waiterGuests.Enabled = false;
        _waiterOrderId = null;
        _waiterOrderInfo.Text = "Смена закрыта: заказы и оплата недоступны.";
        _waiterItemsGrid.DataSource = null;
        _waiterOrdersGrid.DataSource = null;
        UpdateWaiterActionState();
    }

    private async Task LoadWaiterTablesAsync()
    {
        var tables = await Database.ProcedureAsync(
            "dbo.sp_GetWaiterReservationDayTableMap",
            Database.P("@WaiterUserId", _user.UserId),
            Database.P("@ReservationDate", _waiterReservationDay.Value.Date));

        if (!tables.Columns.Contains("TableId"))
            throw new InvalidOperationException(
                "Список столиков получен в неверном формате. Выполните SQL_Update_v3_0_Reservation_Privacy_And_Waiter_Bookings.sql в SSMS и нажмите «Обновить столики».");

        var assignedCount = BindTables(_waiterTable, tables);
        if (_selectedWaiterTableId is int selectedId)
            SelectTableInCombo(_waiterTable, selectedId);
        if (_waiterTable.SelectedItem is TableOption currentTable)
            _selectedWaiterTableId = currentTable.Id;

        var shiftIsOpen = assignedCount > 0;
        _waiterTable.Enabled = shiftIsOpen;
        _waiterGuests.Enabled = shiftIsOpen;
        RenderWaiterTableMap(tables);

        if (!shiftIsOpen)
        {
            _waiterReservationsGrid.DataSource = null;
            _selectedWaiterReservationTableId = null;
        }

        if (!shiftIsOpen && _waiterOrderId is null)
            _waiterOrderInfo.Text = "Нет назначенных столиков. Откройте смену или нажмите «Обновить столики».";
        else if (shiftIsOpen && _waiterOrderId is null)
            _waiterOrderInfo.Text = $"Назначено столиков: {assignedCount}. Выберите столик на схеме и создайте заказ.";

        UpdateWaiterActionState();
    }

    private async Task LoadWaiterReservationsForSelectedTableAsync(int tableId)
    {
        if (!_user.IsWaiter || IsDisposed)
            return;

        _waiterReservationsGrid.DataSource = await Database.ProcedureAsync(
            "dbo.sp_GetWaiterReservationsByTableAndDate",
            Database.P("@WaiterUserId", _user.UserId),
            Database.P("@ReservationDate", _waiterReservationDay.Value.Date),
            Database.P("@TableId", tableId));
    }

    private async Task LoadWaiterMenuAsync()
    {
        _waiterMenuData = await Database.ProcedureAsync("dbo.sp_GetAvailableMenu");
        RenderDishCards(_waiterCards, _waiterMenuData, _waiterSearch.Text, AddDishFromWaiterCardAsync);
    }

    private async Task LoadWaiterOrdersAsync()
    {
        _waiterOrdersGrid.DataSource = await Database.ProcedureAsync("dbo.sp_GetOrdersForWaiter", Database.P("@UserId", _user.UserId));
        SelectGridRowById(_waiterOrdersGrid, "OrderId", _waiterOrderId);
        UpdateWaiterActionState();
    }

    private async Task CreateWaiterOrderAsync()
    {
        if (_waiterTable.SelectedItem is not TableOption table)
        {
            Info("Сначала откройте смену и выберите свой столик.");
            return;
        }
        var result = await Database.ProcedureAsync(
            "dbo.sp_CreateOrderForWaiter",
            Database.P("@WaiterUserId", _user.UserId),
            Database.P("@TableNumber", table.Number),
            Database.P("@GuestCount", Convert.ToInt32(_waiterGuests.Value)));
        _waiterOrderId = ReadId(result, "OrderId");
        _waiterOrderInfo.Text = _waiterOrderId is null ? "Заказ создан" : $"Текущий заказ №{_waiterOrderId}";
        if (_waiterSendOrderButton is not null) _waiterSendOrderButton.Enabled = _waiterOrderId is not null;
        ShowResult(result);
        await LoadWaiterOrdersAsync();
    }

    private async Task LoadWaiterItemsAsync()
    {
        if (!TryGetId(_waiterOrdersGrid, "OrderId", out var orderId))
        {
            _waiterItemsGrid.DataSource = null;
            UpdateWaiterActionState();
            return;
        }

        _waiterOrderId = orderId;
        _waiterOrderInfo.Text = $"Текущий заказ №{orderId}";
        _waiterItemsGrid.DataSource = await Database.ProcedureAsync("dbo.sp_GetOrderItems", Database.P("@OrderId", orderId));
        UpdateWaiterActionState();
    }

    private async Task AddDishFromWaiterCardAsync(int dishId)
    {
        if (_waiterOrderId is null)
        {
            Info("Сначала создайте заказ, затем добавляйте блюда карточками.");
            return;
        }
        await AddDishAsync(_waiterOrderId.Value, dishId, RefreshWaiterAsync);
    }

    private async Task RemoveFromWaiterAsync()
    {
        if (_waiterOrderId is null || !TryGetId(_waiterItemsGrid, "DishId", out var dishId))
        {
            Info("Выберите блюдо в текущем заказе.");
            return;
        }
        await RemoveDishAsync(_waiterOrderId.Value, dishId, RefreshWaiterAsync);
    }

    private async Task FinalizeWaiterAsync()
    {
        if (_waiterOrderId is null)
        {
            Info("Сначала создайте или выберите заказ.");
            return;
        }

        await FinalizeAsync(_waiterOrderId.Value, RefreshWaiterAsync);
        _waiterOrderId = null;
        _waiterOrderInfo.Text = "Заказ отправлен на кухню. Выберите следующий заказ.";
        _waiterItemsGrid.DataSource = null;
        UpdateWaiterActionState();
    }

    private async Task ServeSelectedOrderAsync()
    {
        if (!TryGetId(_waiterOrdersGrid, "OrderId", out var orderId))
        {
            Info("Выберите заказ со статусом «Принят на выдачу».");
            return;
        }

        var result = await Database.ProcedureAsync(
            "dbo.sp_WaiterServeOrder",
            Database.P("@WaiterUserId", _user.UserId),
            Database.P("@OrderId", orderId));
        ShowResult(result);
        _waiterOrderId = orderId;
        await RefreshWaiterAsync();
        await LoadTablesAsync();
    }

    private async Task CreateBillForSelectedOrderAsync()
    {
        if (!TryGetId(_waiterOrdersGrid, "OrderId", out var orderId))
        {
            Info("Выберите выданный клиенту заказ.");
            return;
        }

        var result = await Database.ProcedureAsync(
            "dbo.sp_WaiterCreateBill",
            Database.P("@WaiterUserId", _user.UserId),
            Database.P("@OrderId", orderId));
        ShowResult(result);
        _waiterOrderId = orderId;
        await RefreshWaiterAsync();
    }

    private async Task CloseBillForSelectedOrderAsync()
    {
        if (!TryGetId(_waiterOrdersGrid, "OrderId", out var orderId))
        {
            Info("Выберите заказ со счётом, ожидающим оплаты.");
            return;
        }

        var paymentMethod = Convert.ToString(_paymentMethod.SelectedItem);
        if (string.IsNullOrWhiteSpace(paymentMethod))
        {
            Info("Выберите способ оплаты.");
            return;
        }

        var confirmation = MessageBox.Show(
            "Подтвердить оплату и закрыть счёт? После этого столик станет свободным.",
            "White Rabbit",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question);
        if (confirmation != DialogResult.Yes) return;

        var result = await Database.ProcedureAsync(
            "dbo.sp_WaiterCloseBill",
            Database.P("@WaiterUserId", _user.UserId),
            Database.P("@OrderId", orderId),
            Database.P("@PaymentMethod", paymentMethod));
        ShowResult(result);
        _waiterOrderId = null;
        _waiterItemsGrid.DataSource = null;
        _waiterOrderInfo.Text = "Счёт закрыт. Столик освобождён.";
        await RefreshWaiterAsync();
        await LoadTablesAsync();
    }

    private async Task RefreshClientAsync()
    {
        await LoadClientTablesAsync();
        await LoadClientMenuAsync();
        await LoadClientCartAsync();
        await LoadClientOrderStatusesAsync();
        await LoadReservationTableMapAsync();
    }

    private async Task LoadClientTablesAsync()
    {
        var tables = await Database.ProcedureAsync("dbo.sp_GetAvailableTables");
        BindTables(_clientTable, tables);
    }

    private async Task LoadClientMenuAsync()
    {
        _clientMenuData = await Database.ProcedureAsync("dbo.sp_GetAvailableMenu");
        RenderDishCards(_clientCards, _clientMenuData, _clientSearch.Text, AddDishFromClientCardAsync);
    }

    private async Task CreateClientOrderAsync()
    {
        if (_clientTable.SelectedItem is not TableOption table)
        {
            Info("Выберите свободный столик.");
            return;
        }
        var result = await Database.ProcedureAsync(
            "dbo.sp_CreateClientAppOrder",
            Database.P("@UserId", _user.UserId),
            Database.P("@TableNumber", table.Number),
            Database.P("@GuestCount", Convert.ToInt32(_clientGuests.Value)));
        _clientOrderId = ReadId(result, "OrderId");
        _clientOrderInfo.Text = _clientOrderId is null ? "Корзина создана" : $"Ваш заказ №{_clientOrderId}";
        ShowResult(result);
        await LoadClientCartAsync();
    }

    private async Task LoadClientCartAsync()
    {
        if (_clientOrderId is null)
        {
            _clientCartGrid.DataSource = null;
            _cartSummary.Text = "Корзина пуста";
            return;
        }
        var cart = await Database.ProcedureAsync("dbo.sp_GetOrderItems", Database.P("@OrderId", _clientOrderId.Value));
        _clientCartGrid.DataSource = cart;
        _cartSummary.Text = BuildCartSummary(cart);
    }

    private async Task LoadClientOrderStatusesAsync()
    {
        _clientOrderStatusesGrid.DataSource = await Database.ProcedureAsync(
            "dbo.sp_GetClientOrderStatuses",
            Database.P("@UserId", _user.UserId));
    }

    private async Task AddDishFromClientCardAsync(int dishId)
    {
        if (_clientOrderId is null)
        {
            Info("Сначала выберите столик и нажмите «Начать заказ».");
            return;
        }
        await AddDishAsync(_clientOrderId.Value, dishId, LoadClientCartAsync);
    }

    private async Task RemoveFromClientAsync()
    {
        if (_clientOrderId is null || !TryGetId(_clientCartGrid, "DishId", out var dishId))
        {
            Info("Выберите блюдо в корзине.");
            return;
        }
        await RemoveDishAsync(_clientOrderId.Value, dishId, LoadClientCartAsync);
    }

    private async Task FinalizeClientAsync()
    {
        if (_clientOrderId is null)
        {
            Info("Сначала начните заказ и добавьте блюда.");
            return;
        }
        await FinalizeAsync(_clientOrderId.Value, LoadClientCartAsync);
        _clientOrderId = null;
        _clientOrderInfo.Text = "Заказ отправлен на кухню";
        _clientCartGrid.DataSource = null;
        _cartSummary.Text = "Корзина пуста";
        if (_user.IsAdmin || _user.IsKitchen) await RefreshKitchenAsync();
    }

    private async Task RefreshKitchenAsync()
    {
        var kitchenOrders = await Database.ProcedureAsync("dbo.sp_GetKitchenOrders");
        _kitchenOrdersGrid.DataSource = HideRowsWithStatus(kitchenOrders, "Принят на выдачу");
        _kitchenDishesGrid.DataSource = await Database.ProcedureAsync("dbo.sp_GetKitchenDishes");
    }

    private async Task UpdateKitchenStatusAsync(string statusCode)
    {
        if (!TryGetId(_kitchenOrdersGrid, "OrderId", out var orderId))
        {
            Info("Выберите заказ.");
            return;
        }
        var result = await Database.ProcedureAsync(
            "dbo.sp_SetKitchenOrderStatus",
            Database.P("@OrderId", orderId),
            Database.P("@NewStatusCode", statusCode));
        ShowResult(result);
        await RefreshKitchenAsync();
    }

    private async Task SetStopListAsync(bool isStopListed)
    {
        if (!TryGetId(_kitchenDishesGrid, "DishId", out var dishId))
        {
            Info("Выберите блюдо.");
            return;
        }
        var result = await Database.ProcedureAsync(
            "dbo.sp_SetDishStopListStatus",
            Database.P("@DishId", dishId),
            Database.P("@IsStopListed", isStopListed),
            Database.P("@ChangedByUserId", _user.UserId),
            Database.P("@Reason", Empty(_stopReason.Text)));
        ShowResult(result);
        await RefreshKitchenAsync();
        if (_user.IsAdmin || _user.IsWaiter) await LoadWaiterMenuAsync();
        if (_user.IsClient) await LoadClientMenuAsync();
    }

    private async Task RefreshAdministrationAsync()
    {
        await LoadAdminEmployeesAsync();
        await LoadAdminTablesAsync();
        await LoadTablesAsync();
        await LoadAdminShiftsAsync();
        await LoadAdminOrderStatusesAsync();
        await LoadAdminSalesReportAsync();
        await LoadAdminStockAsync();
    }

    private async Task LoadAdminEmployeesAsync()
    {
        _adminEmployeesGrid.DataSource = await Database.ProcedureAsync("dbo.sp_GetAdminEmployees");

        var waiters = await Database.ProcedureAsync("dbo.sp_GetAdminWaiters");
        var options = new List<WaiterOption>();
        foreach (DataRow row in waiters.Rows)
        {
            if (!TryGetRowId(row, "UserId", out var userId)) continue;
            options.Add(new WaiterOption(
                userId,
                GetString(row, "Официант", "FullName", "Сотрудник"),
                GetString(row, "Логин", "Login")));
        }
        var previousShiftWaiterId = (_adminShiftWaiter.SelectedItem as WaiterOption)?.UserId;
        BindComboBoxItems(_adminShiftWaiter, options, previousShiftWaiterId);

        var filterOptions = new List<WaiterOption> { new(0, "Все официанты", string.Empty) };
        filterOptions.AddRange(options);
        var previousFilterUserId = (_adminShiftFilterWaiter.SelectedItem as WaiterOption)?.UserId ?? 0;
        BindComboBoxItems(_adminShiftFilterWaiter, filterOptions, previousFilterUserId);
    }

    private async Task LoadAdminTablesAsync()
    {
        var tables = await Database.ProcedureAsync("dbo.sp_GetAllRestaurantTables");
        _adminShiftTables.Items.Clear();
        foreach (DataRow row in tables.Rows)
        {
            if (!TryGetRowId(row, "TableId", out var id)) continue;
            _adminShiftTables.Items.Add(new TableOption(
                id,
                TryGetNumber(row, "TableNumber", "№ столика"),
                TryGetNumber(row, "SeatsCount", "Мест"),
                GetString(row, "HallZone", "Зона")));
        }
    }

    private async Task LoadAdminShiftsAsync()
    {
        var waiterId = _adminShiftFilterWaiter.SelectedItem is WaiterOption waiter && waiter.UserId > 0
            ? waiter.UserId
            : (int?)null;
        var statusCode = _adminShiftFilterStatus.SelectedItem is FilterOption status && status.Code != "ALL"
            ? status.Code
            : null;
        var shiftType = _adminShiftFilterType.SelectedItem is FilterOption type && type.Code != "ALL"
            ? type.Code
            : null;

        _adminShiftsGrid.DataSource = await Database.ProcedureAsync(
            "dbo.sp_GetAdminWaiterShiftsFiltered",
            Database.P("@ShiftDate", _adminShiftFilterDate.Checked ? _adminShiftFilterDate.Value.Date : null),
            Database.P("@WaiterUserId", waiterId),
            Database.P("@StatusCode", statusCode),
            Database.P("@ShiftType", shiftType));
    }

    private async Task LoadAdminOrderStatusesAsync()
    {
        _adminOrderStatusesGrid.DataSource = await Database.ProcedureAsync("dbo.sp_AdminGetOrderStatuses");
    }

    private async Task AutoCloseExpiredShiftsAsync()
    {
        var result = await Database.ProcedureAsync("dbo.sp_AutoCloseExpiredWaiterShifts");
        var closedCount = result.Rows.Count > 0 && result.Columns.Contains("ClosedCount")
            ? TryGetNumber(result.Rows[0], "ClosedCount")
            : 0;

        if (closedCount > 0)
            await Database.ProcedureAsync("dbo.sp_RebalanceOpenWaiterTables");

        if (_user.IsWaiter && closedCount > 0)
            await RefreshWaiterAsync();
        if (_user.IsAdmin)
        {
            // Обновляется каждую минуту: администратор сразу увидит смену,
            // которую официант открыл самостоятельно.
            await LoadAdminShiftsAsync();
            if (closedCount > 0)
            {
                await LoadAdminOrderStatusesAsync();
                await LoadTablesAsync();
                await LoadAdminReservationTableMapAsync();
            }
        }
    }

    private async Task LoadAdminSalesReportAsync()
    {
        if (_adminSalesTo.Value.Date < _adminSalesFrom.Value.Date)
        {
            Info("Дата окончания периода не может быть раньше даты начала.");
            return;
        }

        var report = await Database.ProcedureAsync(
            "dbo.sp_AdminSalesReport",
            Database.P("@DateFrom", _adminSalesFrom.Value.Date),
            Database.P("@DateTo", _adminSalesTo.Value.Date));

        _adminSalesGrid.DataSource = report;

        var portions = report.AsEnumerable()
            .Sum(row => TryGetNumber(row, "Продано порций"));
        var revenue = report.AsEnumerable()
            .Sum(row => GetDecimal(row, "Выручка, руб."));

        _adminSalesSummary.Text = report.Rows.Count == 0
            ? "За выбранный период оплаченных продаж нет."
            : $"Продано: {portions} порц. · Выручка: {revenue:N2} ₽";
    }

    private async Task LoadAdminStockAsync()
    {
        _adminStockGrid.DataSource = await Database.ProcedureAsync("dbo.sp_AdminGetStock");
        _adminStockHistoryGrid.DataSource = await Database.ProcedureAsync("dbo.sp_AdminGetStockMovements");
    }

    private async Task RestockSelectedDishAsync()
    {
        if (!TryGetId(_adminStockGrid, "DishId", out var dishId))
        {
            Info("Выберите блюдо в таблице остатков.");
            return;
        }

        var quantity = Convert.ToInt32(_adminRestockQuantity.Value);
        if (quantity < 1)
        {
            Info("Укажите количество порций больше нуля.");
            return;
        }

        var result = await Database.ProcedureAsync(
            "dbo.sp_AdminRestockDish",
            Database.P("@AdminUserId", _user.UserId),
            Database.P("@DishId", dishId),
            Database.P("@Quantity", quantity),
            Database.P("@Comment", Empty(_adminRestockComment.Text)));

        ShowResult(result);
        _adminRestockQuantity.Value = 1;
        _adminRestockComment.Clear();
        await LoadAdminStockAsync();
        await RefreshKitchenAsync();
    }

    private async Task AddEmployeeAsync()
    {
        if (_adminEmployeeRole.SelectedItem is not RoleOption role)
        {
            Info("Выберите роль сотрудника.");
            return;
        }

        RequireText(_adminEmployeeLogin, "Введите логин сотрудника.");
        RequireText(_adminEmployeePassword, "Введите пароль сотрудника.");
        RequireText(_adminEmployeeLastName, "Введите фамилию сотрудника.");
        RequireText(_adminEmployeeFirstName, "Введите имя сотрудника.");

        var result = await Database.ProcedureAsync(
            "dbo.sp_AdminCreateEmployee",
            Database.P("@RoleCode", role.Code),
            Database.P("@Login", _adminEmployeeLogin.Text.Trim()),
            Database.P("@Password", _adminEmployeePassword.Text),
            Database.P("@LastName", _adminEmployeeLastName.Text.Trim()),
            Database.P("@FirstName", _adminEmployeeFirstName.Text.Trim()),
            Database.P("@Phone", Empty(_adminEmployeePhone.Text)));

        ShowResult(result);
        _adminEmployeeLogin.Clear();
        _adminEmployeePassword.Clear();
        _adminEmployeeLastName.Clear();
        _adminEmployeeFirstName.Clear();
        _adminEmployeePhone.Clear();
        await RefreshAdministrationAsync();
    }

    private async Task ArchiveSelectedEmployeeAsync()
    {
        if (!TryGetId(_adminEmployeesGrid, "UserId", out var userId))
        {
            Info("Выберите сотрудника в списке.");
            return;
        }

        var confirmation = MessageBox.Show(
            "Удалить сотрудника из рабочего списка? История заказов и смен останется в базе.",
            "White Rabbit",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);

        if (confirmation != DialogResult.Yes) return;

        var result = await Database.ProcedureAsync(
            "dbo.sp_AdminDeactivateEmployee",
            Database.P("@UserId", userId));
        ShowResult(result);
        await RefreshAdministrationAsync();
    }

    private async Task OpenAdminShiftAsync()
    {
        if (!TryGetId(_adminShiftsGrid, "ShiftId", out var shiftId))
        {
            Info("Выберите смену в таблице.");
            return;
        }

        var result = await Database.ProcedureAsync(
            "dbo.sp_AdminOpenWaiterShift",
            Database.P("@AdminUserId", _user.UserId),
            Database.P("@ShiftId", shiftId));
        ShowResult(result);
        await RefreshAdministrationAsync();
    }

    private async Task CloseAdminShiftAsync()
    {
        if (!TryGetId(_adminShiftsGrid, "ShiftId", out var shiftId))
        {
            Info("Выберите смену в таблице.");
            return;
        }

        var reason = ReasonDialog.Ask(
            this,
            "Закрытие смены официанта",
            "Если смена закрывается раньше назначенного времени, укажите причину. После окончания времени поле можно оставить пустым.");
        if (reason is null) return;

        var result = await Database.ProcedureAsync(
            "dbo.sp_AdminCloseWaiterShift",
            Database.P("@AdminUserId", _user.UserId),
            Database.P("@ShiftId", shiftId),
            Database.P("@Reason", Empty(reason)));
        ShowResult(result);
        await RefreshAdministrationAsync();
    }

    private async Task CreateAdminShiftAsync()
    {
        if (_adminShiftWaiter.SelectedItem is not WaiterOption waiter)
        {
            Info("Выберите официанта.");
            return;
        }

        if (_adminShiftEnd.Value <= _adminShiftStart.Value)
        {
            Info("Время окончания смены должно быть позже времени начала.");
            return;
        }

        var result = await Database.ProcedureAsync(
            "dbo.sp_AdminCreateWaiterShift",
            Database.P("@WaiterUserId", waiter.UserId),
            Database.P("@PlannedStartAt", _adminShiftStart.Value),
            Database.P("@PlannedEndAt", _adminShiftEnd.Value));

        ShowResult(result);
        await LoadAdminShiftsAsync();
    }

    private async Task RebalanceOpenWaiterTablesAsync()
    {
        var result = await Database.ProcedureAsync(
            "dbo.sp_RebalanceOpenWaiterTables",
            Database.P("@AdminUserId", _user.UserId),
            Database.P("@ReturnResult", true));
        ShowResult(result);
        await LoadAdminShiftsAsync();
        await LoadTablesAsync();
        await LoadAdminReservationTableMapAsync();
    }

    private async Task AddDishAsync(int orderId, int dishId, Func<Task> after)
    {
        var result = await Database.ProcedureAsync(
            "dbo.sp_AddDishToOrder",
            Database.P("@OrderId", orderId),
            Database.P("@DishId", dishId),
            Database.P("@Quantity", 1));
        ShowResult(result);
        await after();
    }

    private async Task RemoveDishAsync(int orderId, int dishId, Func<Task> after)
    {
        var result = await Database.ProcedureAsync(
            "dbo.sp_RemoveDishFromOrder",
            Database.P("@OrderId", orderId),
            Database.P("@DishId", dishId),
            Database.P("@Quantity", 1));
        ShowResult(result);
        await after();
    }

    private async Task FinalizeAsync(int orderId, Func<Task> after)
    {
        var result = await Database.ProcedureAsync("dbo.sp_FinalizeOrder", Database.P("@OrderId", orderId));
        ShowResult(result);
        await after();
    }

    private void RenderDishCards(FlowLayoutPanel host, DataTable? menu, string filter, Func<int, Task> addDish)
    {
        host.SuspendLayout();
        host.Controls.Clear();

        if (menu is null)
        {
            host.ResumeLayout();
            return;
        }

        var query = filter.Trim();
        foreach (DataRow row in menu.Rows)
        {
            var name = GetString(row, "Блюдо", "DishName", "Название");
            var category = GetString(row, "Категория", "CategoryName");
            if (!string.IsNullOrWhiteSpace(query) &&
                !name.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                !category.Contains(query, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!TryGetRowId(row, "DishId", out var dishId)) continue;
            host.Controls.Add(CreateDishCard(name, category, GetString(row, "Цена, руб.", "Price", "Цена"), GetString(row, "Доступно, порций", "AvailablePortions", "Остаток"), async () => await RunSafeAsync(() => addDish(dishId))));
        }

        if (host.Controls.Count == 0)
        {
            host.Controls.Add(new Label
            {
                Text = "Блюда не найдены.",
                AutoSize = true,
                Font = new Font("Segoe UI", 11),
                ForeColor = Color.DimGray,
                Margin = new Padding(16)
            });
        }

        host.ResumeLayout();
    }

    private static Control CreateDishCard(string name, string category, string price, string stock, Func<Task> add)
    {
        var card = new Panel
        {
            Width = 212,
            Height = 176,
            Margin = new Padding(8),
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle
        };
        var categoryLabel = new Label
        {
            Text = category,
            AutoSize = false,
            Width = 188,
            Height = 22,
            Location = new Point(12, 12),
            Font = new Font("Segoe UI", 8, FontStyle.Bold),
            ForeColor = Accent
        };
        var nameLabel = new Label
        {
            Text = name,
            AutoSize = false,
            Width = 188,
            Height = 48,
            Location = new Point(12, 36),
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Ink
        };
        var priceLabel = new Label
        {
            Text = string.IsNullOrWhiteSpace(price) ? "Цена уточняется" : $"{price} ₽",
            AutoSize = true,
            Location = new Point(12, 88),
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Ink
        };
        var stockLabel = new Label
        {
            Text = string.IsNullOrWhiteSpace(stock) ? string.Empty : $"В наличии: {stock}",
            AutoSize = false,
            Width = 188,
            Height = 20,
            Location = new Point(12, 113),
            Font = new Font("Segoe UI", 8),
            ForeColor = Color.DimGray
        };
        var button = CreateButton("+ Добавить");
        button.Location = new Point(12, 137);
        button.Width = 188;
        button.Height = 30;
        button.Margin = Padding.Empty;
        button.Click += async (_, _) => await add();
        card.Controls.AddRange(new Control[] { categoryLabel, nameLabel, priceLabel, stockLabel, button });
        return card;
    }

    private static string BuildCartSummary(DataTable cart)
    {
        if (cart.Rows.Count == 0) return "Корзина пуста";

        var portions = 0;
        decimal sum = 0;
        foreach (DataRow row in cart.Rows)
        {
            portions += TryGetNumber(row, "Quantity", "Количество", "Порций");
            var lineSum = GetDecimal(row, "Сумма", "Total", "Итого");
            if (lineSum > 0)
            {
                sum += lineSum;
                continue;
            }
            sum += GetDecimal(row, "Цена", "UnitPrice", "Цена, руб.") * TryGetNumber(row, "Quantity", "Количество", "Порций");
        }
        return sum > 0 ? $"Позиций: {portions} · Итого: {sum:N0} ₽" : $"Позиций: {portions}";
    }

    private static void BindComboBoxItems<T>(ComboBox box, IReadOnlyList<T> items, int? preferredItemId = null)
        where T : class
    {
        box.BeginUpdate();
        try
        {
            box.DataSource = null;
            box.DisplayMember = string.Empty;
            box.ValueMember = string.Empty;
            box.Items.Clear();

            foreach (var item in items)
                box.Items.Add(item);

            var selectedIndex = -1;
            if (preferredItemId is int wantedId)
            {
                for (var index = 0; index < box.Items.Count; index++)
                {
                    if (box.Items[index] is WaiterOption waiter && waiter.UserId == wantedId)
                    {
                        selectedIndex = index;
                        break;
                    }
                }
            }

            if (selectedIndex < 0 && box.Items.Count > 0)
                selectedIndex = 0;

            SetComboBoxSelection(box, selectedIndex);
            box.Enabled = box.Items.Count > 0;
        }
        finally
        {
            box.EndUpdate();
        }
    }

    private static int BindTables(ComboBox box, DataTable table)
    {
        var options = new List<TableOption>();
        foreach (DataRow row in table.Rows)
        {
            if (!TryGetRowId(row, "TableId", out var id)) continue;
            options.Add(new TableOption(
                id,
                TryGetNumber(row, "TableNumber", "Номер столика", "№ столика"),
                TryGetNumber(row, "SeatsCount", "Мест", "Количество мест"),
                GetString(row, "HallZone", "Зона", "Зал")));
        }

        // Не используем DataSource для динамически пустого списка.
        // В .NET 10 ComboBox при таком перепривязывании может попытаться
        // установить SelectedIndex = 0 даже при отсутствии элементов.
        box.BeginUpdate();
        try
        {
            box.DataSource = null;
            box.DisplayMember = string.Empty;
            box.ValueMember = string.Empty;
            box.Items.Clear();

            foreach (var option in options)
                box.Items.Add(option);

            SetComboBoxSelection(box, options.Count > 0 ? 0 : -1);
            box.Enabled = options.Count > 0;
        }
        finally
        {
            box.EndUpdate();
        }

        return options.Count;
    }

    private static void SetComboBoxSelection(ComboBox box, int requestedIndex)
    {
        // ComboBox.SelectedIndex принимает только -1 или индекс существующего элемента.
        // Проверка исключает "value (0) must be less than 0" при пустом списке.
        if (requestedIndex >= 0 && requestedIndex < box.Items.Count)
        {
            box.SelectedIndex = requestedIndex;
            return;
        }

        if (box.SelectedIndex != -1)
            box.SelectedIndex = -1;
    }

    private static void ApplyGuestCapacity(ComboBox tables, NumericUpDown guests)
    {
        if (tables.SelectedItem is not TableOption table)
        {
            guests.Minimum = 1;
            guests.Maximum = 4;
            if (guests.Value > guests.Maximum) guests.Value = guests.Maximum;
            return;
        }

        guests.Minimum = 1;
        guests.Maximum = Math.Max(1, table.Seats);
        if (guests.Value > guests.Maximum) guests.Value = guests.Maximum;
    }

    private void UpdateWaiterActionState()
    {
        // Список назначенных столиков заполняется через Items, а не DataSource.
        // Поэтому проверяем наличие элементов: иначе кнопка «Создать заказ» всегда была отключена.
        var shiftIsOpen = _waiterTable.Enabled && _waiterTable.Items.Count > 0;
        var statusCode = GetCurrentRowString(_waiterOrdersGrid, "StatusCode");
        var billIssued = GetCurrentRowBoolean(_waiterOrdersGrid, "BillIssued");
        var billPaid = GetCurrentRowBoolean(_waiterOrdersGrid, "BillPaid");

        if (_waiterCreateOrderButton is not null)
            _waiterCreateOrderButton.Enabled = shiftIsOpen;
        if (_waiterSendOrderButton is not null)
            _waiterSendOrderButton.Enabled = shiftIsOpen && statusCode == "DRAFT";
        if (_waiterServeOrderButton is not null)
            _waiterServeOrderButton.Enabled = shiftIsOpen && statusCode == "ACCEPTED";
        if (_waiterCreateBillButton is not null)
            _waiterCreateBillButton.Enabled = shiftIsOpen && statusCode == "ISSUED" && !billIssued;
        if (_waiterCloseBillButton is not null)
            _waiterCloseBillButton.Enabled = shiftIsOpen && statusCode == "ISSUED" && billIssued && !billPaid;

        _paymentMethod.Enabled = _waiterCloseBillButton?.Enabled == true;
    }

    private static void SelectGridRowById(DataGridView grid, string columnName, int? id)
    {
        if (id is null || grid.Rows.Count == 0) return;

        foreach (DataGridViewRow row in grid.Rows)
        {
            if (row.DataBoundItem is not DataRowView view || !view.Row.Table.Columns.Contains(columnName)) continue;
            if (int.TryParse(Convert.ToString(view.Row[columnName]), out var rowId) && rowId == id.Value)
            {
                grid.ClearSelection();
                row.Selected = true;

                // Первая колонка обычно скрытый технический идентификатор (OrderId/DishId).
                // Выбираем первую ВИДИМУЮ ячейку, чтобы не возникала ошибка WinForms.
                var visibleCell = row.Cells
                    .Cast<DataGridViewCell>()
                    .FirstOrDefault(cell => cell.OwningColumn?.Visible == true);

                if (visibleCell is not null)
                    grid.CurrentCell = visibleCell;
                return;
            }
        }
    }

    private static string GetCurrentRowString(DataGridView grid, string column)
    {
        if (grid.CurrentRow?.DataBoundItem is not DataRowView view) return string.Empty;
        if (!view.Row.Table.Columns.Contains(column)) return string.Empty;
        return Convert.ToString(view.Row[column]) ?? string.Empty;
    }

    private static bool GetCurrentRowBoolean(DataGridView grid, string column)
    {
        if (grid.CurrentRow?.DataBoundItem is not DataRowView view) return false;
        if (!view.Row.Table.Columns.Contains(column)) return false;
        var value = view.Row[column];
        return value != DBNull.Value && Convert.ToBoolean(value);
    }

    private async Task RunSafeAsync(Func<Task> operation)
    {
        try
        {
            UseWaitCursor = true;
            await operation();
        }
        catch (Exception exception)
        {
            CrashReporter.Show("Ошибка операции", exception);
        }
        finally
        {
            UseWaitCursor = false;
        }
    }

    private static void RequireText(TextBox textBox, string message)
    {
        if (string.IsNullOrWhiteSpace(textBox.Text)) throw new InvalidOperationException(message);
    }

    private static string? Empty(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static bool TryGetId(DataGridView grid, string column, out int id)
    {
        id = 0;
        if (grid.CurrentRow?.DataBoundItem is not DataRowView row) return false;
        return TryGetRowId(row.Row, column, out id);
    }

    private static int? ReadId(DataTable table, string column) =>
        table.Rows.Count > 0 && TryGetRowId(table.Rows[0], column, out var id) ? id : null;

    private static bool TryGetRowId(DataRow row, string column, out int id)
    {
        id = 0;
        if (!row.Table.Columns.Contains(column)) return false;
        var value = row[column];
        return value != DBNull.Value && int.TryParse(Convert.ToString(value), out id);
    }

    private static string GetString(DataRow row, params string[] names)
    {
        foreach (var name in names)
        {
            if (!row.Table.Columns.Contains(name)) continue;
            var value = row[name];
            if (value != DBNull.Value && value is not null) return Convert.ToString(value) ?? string.Empty;
        }
        return string.Empty;
    }

    private static int TryGetNumber(DataRow row, params string[] names)
    {
        foreach (var name in names)
        {
            if (!row.Table.Columns.Contains(name)) continue;
            if (int.TryParse(Convert.ToString(row[name]), out var result)) return result;
        }
        return 0;
    }

    private static decimal GetDecimal(DataRow row, params string[] names)
    {
        foreach (var name in names)
        {
            if (!row.Table.Columns.Contains(name)) continue;
            if (decimal.TryParse(Convert.ToString(row[name]), out var result)) return result;
        }
        return 0;
    }

    private static void ShowResult(DataTable table)
    {
        var message = table.Rows.Count > 0 && table.Columns.Contains("Message")
            ? Convert.ToString(table.Rows[0]["Message"])
            : "Готово.";
        MessageBox.Show(message ?? "Готово.", "White Rabbit", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static void Info(string message) =>
        MessageBox.Show(message, "White Rabbit", MessageBoxButtons.OK, MessageBoxIcon.Information);

    private sealed record TableOption(int Id, int Number, int Seats, string Zone)
    {
        public string Display => $"Стол №{Number} · {Seats} мест" + (string.IsNullOrWhiteSpace(Zone) ? string.Empty : $" · {Zone}");
        public override string ToString() => Display;
    }

    private sealed record RoleOption(string Code, string Name)
    {
        public override string ToString() => Name;
    }

    private sealed record WaiterOption(int UserId, string FullName, string Login)
    {
        public string Display => UserId == 0 || string.IsNullOrWhiteSpace(Login) ? FullName : $"{FullName} · {Login}";
        public override string ToString() => Display;
    }

    private sealed record FilterOption(string Code, string Name)
    {
        public override string ToString() => Name;
    }
}
