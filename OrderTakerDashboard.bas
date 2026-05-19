B4A=true
Group=Default Group
ModulesStructureVersion=1
Type=Activity
Version=13.4
@EndOfDesignText@


#Region  Activity Attributes
    #FullScreen: False
    #IncludeTitle: False
#End Region

Sub Process_Globals
	Private xui As XUI
End Sub

Sub Globals
	' Bottom navigation bar panels and labels
	Private pnlBottomNav As Panel
	Private pnlDash As Panel, lblDash As Label, lblDashIcon As Label
	Private pnlOrders As Panel, lblOrders As Label, lblOrdersIcon As Label
	Private pnlInventory As Panel, lblInventory As Label, lblInventoryIcon As Label
	Private pnlHistory As Panel, lblHistory As Label, lblHistoryIcon As Label

	' Content panels (one per tab)
	Private pnlContent As Panel
	Private pnlContentDash As Panel
	Private pnlContentOrders As Panel
	Private pnlContentInventory As Panel
	Private pnlContentHistory As Panel

	' Top bar
	Private pnlTop As Panel
	Private pnlDim As Panel
	Private lblLoggedInUser As Label
	Private lbllogout As Label
	Private lblperson As Label

	' Dashboard tab
	Private lblFetchStatus As Label
	Private lblCacheInfo As Label
	Private bttnFetchProducts As Button

	' Orders tab
	Private clvContentOrders As CustomListView
	Private etContentSearchOrder As EditText
	Private bttnAddOrder As Button
	Private pnlContentOrdersPagination As Panel
	Private lblOrdersPage As Label
	Private bttnOrdersPrev As Button
	Private bttnOrdersNext As Button
	Private currentOrdersPage As Int = 1
	Private totalOrdersPages As Int = 1
	Private Const ORDERS_PAGE_SIZE As Int = 10

	' Inventory tab
	Private clvInventory As CustomListView

	' History tab
	Private clvContentHistory As CustomListView
	Private pnlContentHistoryPagination As Panel
	Private lblHistoryPage As Label
	Private bttnHistoryPrev As Button
	Private bttnHistoryNext As Button
	Private currentHistoryPage As Int = 1
	Private totalHistoryPages As Int = 1
	Private Const HISTORY_PAGE_SIZE As Int = 10
	Private lblHistoryTotalOrderSync As Label
	Private lblHistoryTotalAmountSynced As Label
	Private lblHistoryTotalItemsSynced As Label
	Private expandedDates As Map

	' Track active HTTP jobs so we can release/cancel them on pause
	Private currentFetchJob As HttpJob
	Private currentCustomerJob As HttpJob
	Private currentSyncJob As HttpJob
	Private syncOrdersCompletedCount As Int
	'Dashboard Status
	Private lblPendingSync As Label
	Private lblTodaySales As Label
	Private lblTodaysOrders As Label
	Private bttnSyncOrdersNow As Button
	
	Private pnllineChart As Panel
	Private pnlPiechart As Panel
End Sub

Sub Activity_Create(FirstTime As Boolean)
	Activity.LoadLayout("OrderTakerDashboard")
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	SetupDashboardCards

	Dim displayName As String = Main.LoggedInUser
	If Main.LoggedInUserFullName <> "" Then
		displayName = Main.LoggedInUserFullName
	End If
	lblLoggedInUser.Text = "Welcome, " & displayName

	expandedDates.Initialize
	SetupOrdersDatabaseTables
	SetupOrdersPagination
	SetupHistoryPagination
	ShowPanel(pnlContentDash)
	UpdateDashboardStatusLabels
End Sub

Sub Activity_Resume
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	LoadOrdersIntoList
	UpdateDashboardStatusLabels
	FetchAssignedStockForLocalCache
	DrawWeeklySalesChart
	DrawOrderStatusPieChart
End Sub


Sub Activity_Pause(UserClosed As Boolean)
	' Release any pending network jobs to avoid events firing after activity is paused/closed
	If currentFetchJob <> Null Then
		Try
			If currentFetchJob.IsInitialized Then currentFetchJob.Release
		Catch
			Log(LastException.Message)
		End Try
		currentFetchJob = Null
	End If

	If currentCustomerJob <> Null Then
		Try
			If currentCustomerJob.IsInitialized Then currentCustomerJob.Release
		Catch
			Log(LastException.Message)
		End Try
		currentCustomerJob = Null
	End If

	If currentSyncJob <> Null Then
		Try
			If currentSyncJob.IsInitialized Then currentSyncJob.Release
		Catch
			Log("Activity_Pause currentSyncJob release error: " & LastException.Message)
		End Try
		currentSyncJob = Null
	End If
End Sub

' Creates orders/order_items tables if they don't exist
Private Sub SetupOrdersDatabaseTables
	Main.SQLProducts.ExecNonQuery( _
        "CREATE TABLE IF NOT EXISTS orders (" & _
        "order_id INTEGER PRIMARY KEY AUTOINCREMENT, " & _
        "vendor_id INTEGER, " & _
        "user_id INTEGER, " & _
        "date_created TEXT, " & _
        "status TEXT, " & _
        "total_amount REAL)")
        
	Main.SQLProducts.ExecNonQuery( _
        "CREATE TABLE IF NOT EXISTS order_items (" & _
        "order_item_id INTEGER PRIMARY KEY AUTOINCREMENT, " & _
        "order_id INTEGER, " & _
        "product_id INTEGER, " & _
        "quantity INTEGER, " & _
        "price REAL)")

	EnsureLocalSchema
End Sub

' Safe schema migration: add only missing columns one by one
Sub EnsureLocalSchema
	If Main.SQLProducts.IsInitialized = False Then
		Log("EnsureLocalSchema skipped: SQLProducts not initialized")
		Return
	End If

	' orders table
	AddColumnIfMissing("orders", "user_id", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "vendor_id", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "convention_id", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "sync_status", "TEXT DEFAULT 'Holding'")
	AddColumnIfMissing("orders", "synced_at", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "transaction_number", "TEXT")
	AddColumnIfMissing("orders", "device_id", "TEXT")
	' customer fields for orders (added safely if missing)
	AddColumnIfMissing("orders", "customer_id", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "customer_code", "TEXT DEFAULT ''")
	AddColumnIfMissing("orders", "customer_name", "TEXT DEFAULT ''")
	AddColumnIfMissing("orders", "customer_owner", "TEXT DEFAULT ''")
	AddColumnIfMissing("orders", "customer_address", "TEXT DEFAULT ''")
	AddColumnIfMissing("orders", "item_count", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "booking", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "prepaid", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "is_paid", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "is_received", "INTEGER DEFAULT 0")
	AddColumnIfMissing("orders", "is_booked", "INTEGER DEFAULT 0")

	' order_items table
	AddColumnIfMissing("order_items", "fulfillment_status", "TEXT DEFAULT ''")
	AddColumnIfMissing("order_items", "payment_status", "TEXT DEFAULT ''")
	AddColumnIfMissing("order_items", "delivery_status", "TEXT DEFAULT ''")
	' items table stock cache
	AddColumnIfMissing("items", "assigned_stock", "INTEGER DEFAULT 0")
	AddColumnIfMissing("items", "used_stock", "INTEGER DEFAULT 0")
	AddColumnIfMissing("items", "remaining_stock", "INTEGER DEFAULT 0")
End Sub

Sub AddColumnIfMissing(TableName As String, ColumnName As String, ColumnDef As String)
	If HasColumn(TableName, ColumnName) Then Return

	Try
		Main.SQLProducts.ExecNonQuery("ALTER TABLE " & TableName & " ADD COLUMN " & ColumnName & " " & ColumnDef)
		Log("Added column: " & TableName & "." & ColumnName)
	Catch
		Log("AddColumnIfMissing error on " & TableName & "." & ColumnName & ": " & LastException.Message)
	End Try
End Sub

Sub HasColumn(TableName As String, ColumnName As String) As Boolean
	Dim rs As ResultSet
	Try
		rs = Main.SQLProducts.ExecQuery("PRAGMA table_info(" & TableName & ")")
		Do While rs.NextRow
			If rs.GetString("name").ToLowerCase = ColumnName.ToLowerCase Then
				rs.Close
				Return True
			End If
		Loop
		rs.Close
		Return False
	Catch
		If rs.IsInitialized Then rs.Close
		Log("HasColumn error on " & TableName & "." & ColumnName & ": " & LastException.Message)
		Return False
	End Try
End Sub

' ======================
' BOTTOM NAVIGATION
' ======================

Private Sub ShowPanel(panelToShow As Panel)
	pnlContentDash.Visible = False
	pnlContentOrders.Visible = False
	pnlContentInventory.Visible = False
	pnlContentHistory.Visible = False

	panelToShow.Visible = True

	Dim inactiveColor As Int = Colors.RGB(158, 158, 158)
	lblDashIcon.TextColor = inactiveColor
	lblDash.TextColor = inactiveColor
	lblOrdersIcon.TextColor = inactiveColor
	lblOrders.TextColor = inactiveColor
	lblInventoryIcon.TextColor = inactiveColor
	lblInventory.TextColor = inactiveColor
	lblHistoryIcon.TextColor = inactiveColor
	lblHistory.TextColor = inactiveColor

	Dim activeColor As Int = Colors.RGB(33, 150, 243)
	If panelToShow = pnlContentDash Then
		lblDashIcon.TextColor = activeColor
		lblDash.TextColor = activeColor
	Else If panelToShow = pnlContentOrders Then
		lblOrdersIcon.TextColor = activeColor
		lblOrders.TextColor = activeColor
	Else If panelToShow = pnlContentInventory Then
		lblInventoryIcon.TextColor = activeColor
		lblInventory.TextColor = activeColor
	Else If panelToShow = pnlContentHistory Then
		lblHistoryIcon.TextColor = activeColor
		lblHistory.TextColor = activeColor
	End If
End Sub

Private Sub pnlDash_Click
	ShowPanel(pnlContentDash)
	UpdateDashboardStatusLabels
	DrawWeeklySalesChart
	DrawOrderStatusPieChart
End Sub


Private Sub pnlOrders_Click
	ShowPanel(pnlContentOrders)
	bttnAddOrder.Visible = True
	bttnAddOrder.BringToFront
	If pnlContentOrdersPagination.IsInitialized Then pnlContentOrdersPagination.Visible = True
	LoadOrdersIntoList
End Sub

Private Sub pnlInventory_Click
	ShowPanel(pnlContentInventory)
	FetchAssignedStockForLocalCache
End Sub

Private Sub pnlHistory_Click
	ShowPanel(pnlContentHistory)
	If pnlContentHistoryPagination.IsInitialized Then pnlContentHistoryPagination.Visible = True
	LoadHistoryIntoCustomListView
	If pnlContentOrdersPagination.IsInitialized Then pnlContentOrdersPagination.Visible = False
End Sub

Private Sub lbllogout_Click
	CallSub(Main, "ResetSessionForLogout")
	StartActivity(Main)
	Activity.Finish
End Sub

Private Sub pnlDim_Click
End Sub

' ======================
' ORDERS TAB
' ======================

Private Sub SetupOrdersPagination
	If pnlContentOrdersPagination.IsInitialized = False Then Return

	pnlContentOrdersPagination.RemoveAllViews
	pnlContentOrdersPagination.Visible = True

	Dim barHeight As Int = pnlContentOrdersPagination.Height
	If barHeight <= 0 Then barHeight = 48dip

	bttnOrdersPrev.Initialize("bttnOrdersPrev")
	bttnOrdersPrev.Text = "Prev"
	bttnOrdersPrev.Enabled = False
	pnlContentOrdersPagination.AddView(bttnOrdersPrev, 8dip, 6dip, 64dip, barHeight - 12dip)

	lblOrdersPage.Initialize("")
	lblOrdersPage.Text = "1 / 1"
	lblOrdersPage.TextColor = Colors.Gray
	lblOrdersPage.TextSize = 14
	lblOrdersPage.Gravity = Gravity.CENTER
	pnlContentOrdersPagination.AddView(lblOrdersPage, 76dip, 6dip, pnlContentOrdersPagination.Width - 152dip, barHeight - 12dip)

	bttnOrdersNext.Initialize("bttnOrdersNext")
	bttnOrdersNext.Text = "Next"
	bttnOrdersNext.Enabled = False
	pnlContentOrdersPagination.AddView(bttnOrdersNext, pnlContentOrdersPagination.Width - 72dip, 6dip, 64dip, barHeight - 12dip)
End Sub

Private Sub RefreshOrdersPaginationBar
	If lblOrdersPage.IsInitialized = False Then Return

	If totalOrdersPages < 1 Then totalOrdersPages = 1
	If currentOrdersPage < 1 Then currentOrdersPage = 1
	If currentOrdersPage > totalOrdersPages Then currentOrdersPage = totalOrdersPages

	lblOrdersPage.Text = currentOrdersPage & " / " & totalOrdersPages
	bttnOrdersPrev.Enabled = currentOrdersPage > 1
	bttnOrdersNext.Enabled = currentOrdersPage < totalOrdersPages
End Sub

Private Sub GetOrdersWhereClause(searchText As String) As String
	Dim sql As String = "FROM orders WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') <> 'Cancelled' "
	If searchText <> "" Then
		sql = sql & "AND LOWER('order #' || CAST(order_id AS TEXT)) LIKE ? "
	End If
	Return sql
End Sub

Private Sub GetOrdersArgs(searchText As String, includePaging As Boolean) As String()
	If searchText = "" And includePaging = False Then
		Return Array As String(Main.VENDOR_ID, Main.LoggedInUserID)
	Else If searchText <> "" And includePaging = False Then
		Return Array As String(Main.VENDOR_ID, Main.LoggedInUserID, "%" & searchText & "%")
	Else If searchText = "" And includePaging = True Then
		Return Array As String(Main.VENDOR_ID, Main.LoggedInUserID, ORDERS_PAGE_SIZE, (currentOrdersPage - 1) * ORDERS_PAGE_SIZE)
	Else
		Return Array As String(Main.VENDOR_ID, Main.LoggedInUserID, "%" & searchText & "%", ORDERS_PAGE_SIZE, (currentOrdersPage - 1) * ORDERS_PAGE_SIZE)
	End If
End Sub

Private Sub GetOrdersCount(searchText As String) As Int
	Dim sql As String = "SELECT COUNT(*) AS total " & GetOrdersWhereClause(searchText)
	Dim args() As String = GetOrdersArgs(searchText, False)
	Dim rs As ResultSet = Main.SQLProducts.ExecQuery2(sql, args)
	Dim total As Int = 0
	If rs.NextRow Then total = rs.GetInt("total")
	rs.Close
	Return total
End Sub

Private Sub LoadOrdersIntoList
	clvContentOrders.Clear

	Dim searchText As String = etContentSearchOrder.Text.Trim.ToLowerCase
	Dim totalOrders As Int = GetOrdersCount(searchText)
	totalOrdersPages = Ceil(totalOrders / ORDERS_PAGE_SIZE)
	If totalOrdersPages < 1 Then totalOrdersPages = 1
	If currentOrdersPage > totalOrdersPages Then currentOrdersPage = totalOrdersPages
	If currentOrdersPage < 1 Then currentOrdersPage = 1

	Dim sql As String = "SELECT *, IFNULL(is_paid, 0) AS is_paid, IFNULL(is_received, 0) AS is_received, IFNULL(is_booked, 0) AS is_booked " & GetOrdersWhereClause(searchText) & "ORDER BY date_created DESC LIMIT ? OFFSET ?"
	Dim args() As String = GetOrdersArgs(searchText, True)
	Dim rs As ResultSet = Main.SQLProducts.ExecQuery2(sql, args)

	RefreshOrdersPaginationBar

	If rs.RowCount = 0 Then
		Dim pnlEmpty As Panel ' new
		pnlEmpty.Initialize("") ' new
		pnlEmpty.Color = Colors.Transparent ' new
		pnlEmpty.SetLayout(0, 0, clvContentOrders.AsView.Width, 70dip) ' new

		Dim lblEmpty As Label ' new
		lblEmpty.Initialize("") ' new
		lblEmpty.Text = "No matching order found" ' new
		lblEmpty.TextColor = Colors.Gray ' new
		lblEmpty.TextSize = 14 ' new
		lblEmpty.Gravity = Gravity.CENTER ' new

		pnlEmpty.AddView(lblEmpty, 0, 15dip, clvContentOrders.AsView.Width, 30dip) ' new
		clvContentOrders.Add(pnlEmpty, 0) ' new

		rs.Close
		Return
	End If

	Dim lastDateString As String = ""
	
	Do While rs.NextRow
		' Get the order date
		Dim orderDateTicks As Long = 0
		Try
			orderDateTicks = rs.GetLong("date_created")
		Catch
			orderDateTicks = 0
		End Try
		
		Dim currentDateString As String = DateTime.Date(orderDateTicks)
		
		' If date changed, add a date header
		If currentDateString <> lastDateString Then
			lastDateString = currentDateString
			
			' Create date header panel
			Dim pnlHeader As Panel
			pnlHeader.Initialize("")
			pnlHeader.SetLayout(0, 0, clvContentOrders.AsView.Width, 40dip)
			pnlHeader.Color = Colors.RGB(240, 240, 240)
			
			Dim lblDateHeader As Label
			lblDateHeader.Initialize("")
			lblDateHeader.Text = FormatDateHeader(orderDateTicks)
			lblDateHeader.TextSize = 14
			lblDateHeader.TextColor = Colors.RGB(66, 66, 66)
			lblDateHeader.Typeface = Typeface.DEFAULT_BOLD
			lblDateHeader.Gravity = Gravity.LEFT
			pnlHeader.AddView(lblDateHeader, 10dip, 8dip, clvContentOrders.AsView.Width - 20dip, 24dip)
			
			clvContentOrders.Add(pnlHeader, -1)
		End If
		
		' Add order item
		Dim pnl As Panel
		pnl.Initialize("")
		pnl.SetLayout(0, 0, clvContentOrders.AsView.Width, 100dip)
		pnl.Color = Colors.White

		Dim lblOrderID As Label
		lblOrderID.Initialize("")
		lblOrderID.Text = "Order #" & rs.GetInt("order_id")
		lblOrderID.TextSize = 16
		lblOrderID.Typeface = Typeface.DEFAULT_BOLD ' new
		lblOrderID.SetLayout(10dip, 6dip, 45%x, 24dip) ' new

		Dim lblSync As Label
		lblSync.Initialize("")
		lblSync.Text = GetOrderSyncStatusLabel(rs.GetString("sync_status"))
		lblSync.TextSize = 11
		lblSync.TextColor = GetOrderSyncStatusColor(rs.GetString("sync_status"))
		lblSync.Gravity = Gravity.LEFT
		lblSync.Color = Colors.Transparent
		lblSync.SetLayout(10dip, 58dip, 120dip, 16dip)

		Dim orderIsPaid As Boolean = rs.GetInt("is_paid") = 1
		Dim orderIsReceived As Boolean = rs.GetInt("is_received") = 1
		Dim orderIsBooked As Boolean = rs.GetInt("is_booked") = 1

		Dim lblOrderStatus As Label
		lblOrderStatus.Initialize("")
		Dim paidTag As String = IIf(orderIsPaid, "✓Paid", "✗Unpaid")
		Dim receivedTag As String = IIf(orderIsReceived, "✓Recv", "✗NoRecv")
		Dim bookedTag As String = IIf(orderIsBooked, "✓Bkd", "✗NoBk")
		lblOrderStatus.Text = paidTag & "  " & receivedTag & "  " & bookedTag
		lblOrderStatus.TextSize = 10
		lblOrderStatus.TextColor = Colors.RGB(80, 80, 80)
		lblOrderStatus.Gravity = Gravity.LEFT
		lblOrderStatus.SetLayout(10dip, 78dip, 70%x, 16dip)

		Dim lblTotal As Label
		lblTotal.Initialize("")
		lblTotal.Text = "Total: ₱" & NumberFormat2(rs.GetDouble("total_amount"), 1, 2, 2, False)
		lblTotal.SetLayout(10dip, 36dip, 55%x, 25dip)

		Dim bttnCopyOrder As Button
		bttnCopyOrder.Initialize("bttnCopyOrder")
		bttnCopyOrder.Text = "Copy"
		bttnCopyOrder.Tag = rs.GetInt("order_id")
		bttnCopyOrder.TextSize = 11
		bttnCopyOrder.TextColor = Colors.White
		bttnCopyOrder.Gravity = Gravity.CENTER
		bttnCopyOrder.Color = Colors.RGB(33, 150, 243)

		Dim bttnDeleteOrder As Button
		bttnDeleteOrder.Initialize("bttnDeleteOrder")
		bttnDeleteOrder.Text = "Del"
		bttnDeleteOrder.Tag = rs.GetInt("order_id")
		bttnDeleteOrder.TextSize = 11
		bttnDeleteOrder.TextColor = Colors.White
		bttnDeleteOrder.Gravity = Gravity.CENTER
		bttnDeleteOrder.Color = Colors.RGB(244, 67, 54)

		pnl.AddView(lblOrderID, lblOrderID.Left, lblOrderID.Top, lblOrderID.Width, lblOrderID.Height)
		pnl.AddView(lblSync, lblSync.Left, lblSync.Top, lblSync.Width, lblSync.Height)
		pnl.AddView(lblTotal, lblTotal.Left, lblTotal.Top, lblTotal.Width, lblTotal.Height)
		pnl.AddView(lblOrderStatus, lblOrderStatus.Left, lblOrderStatus.Top, lblOrderStatus.Width, lblOrderStatus.Height)
		pnl.AddView(bttnCopyOrder, pnl.Width - 128dip, 16dip, 62dip, 35dip)
		pnl.AddView(bttnDeleteOrder, pnl.Width - 62dip, 16dip, 60dip, 35dip)

		clvContentOrders.Add(pnl, rs.GetInt("order_id"))
	Loop
	rs.Close
End Sub


Private Sub clvContentOrders_ItemClick(Index As Int, Value As Object)
	Dim orderID As Int = Value
	ShowOrderDetails(orderID)
End Sub

Private Sub clvContentOrders_ItemLongClick(Index As Int, Value As Object)
End Sub

Private Sub bttnCopyOrder_Click
	Dim orderID As Int = GetOrderIdFromSender(Sender)
	If orderID <= 0 Then Return

	Main.COPY_ORDER_SOURCE_ID = orderID
	ToastMessageShow("Copying order...", False)
	StartActivity(addOrderActivity)
End Sub

Private Sub bttnDeleteOrder_Click
	Dim orderID As Int = GetOrderIdFromSender(Sender)
	If orderID <= 0 Then Return

	Msgbox2Async("Delete this order from the local list?", "Confirm Delete", "Delete", "", "Cancel", Null, False)
	Wait For Msgbox_Result (Result As Int)
	If Result <> DialogResponse.POSITIVE Then Return

	Try
		Main.SQLProducts.ExecNonQuery2("UPDATE orders SET sync_status = 'Cancelled' WHERE order_id = ?", Array As Object(orderID))
		ToastMessageShow("Order removed from the list.", False)
		LoadOrdersIntoList
		LoadHistoryIntoCustomListView
		UpdateDashboardStatusLabels
	Catch
		Log("bttnDeleteOrder_Click error: " & LastException.Message)
		ToastMessageShow("Unable to delete order.", True)
	End Try
End Sub

Private Sub GetOrderIdFromSender(senderObject As Object) As Int
	Dim viewSender As View = senderObject
	If viewSender.IsInitialized = False Then Return 0
	If IsNumber(viewSender.Tag) = False Then Return 0
	Return viewSender.Tag
End Sub

' ======================
' INVENTORY TAB
' ======================

Private Sub LoadInventoryItemsIntoCLV
	EnsureLocalSchema

	If clvInventory.IsInitialized = False Then
		Log("LoadInventoryItemsIntoCLV skipped: clvInventory not initialized")
		Return
	End If

	clvInventory.Clear
	clvInventory.Add(CreateRequestStocksRow, "request")

	Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
        "SELECT * FROM items WHERE is_active = 1 AND vendor_id = ? ORDER BY item_name", _
        Array As String(Main.VENDOR_ID))

	If rs.RowCount = 0 Then
		rs.Close
		ShowEmptyInventoryMessage
		Return
	End If

	Do While rs.NextRow
		Dim itemId As Int = rs.GetInt("item_id")
		Dim itemName As String = rs.GetString("item_name")
		Dim itemCode As String = rs.GetString("item_code")
		Dim unitPrice As Double = rs.GetDouble("unit_price")

		Dim assignedStock As Int = 0
		If HasColumnValue(rs, "assigned_stock") Then assignedStock = rs.GetInt("assigned_stock")

		Dim usedStock As Int = 0
		If HasColumnValue(rs, "used_stock") Then usedStock = rs.GetInt("used_stock")

		Dim remainingStock As Int = 0
		If HasColumnValue(rs, "remaining_stock") Then
			remainingStock = rs.GetInt("remaining_stock")
		Else
			remainingStock = assignedStock - usedStock
			If remainingStock < 0 Then remainingStock = 0
		End If

		clvInventory.Add(CreateInventoryRow(itemName, itemCode, unitPrice, assignedStock, usedStock, remainingStock), itemId)
	Loop
	rs.Close
End Sub

Private Sub clvInventory_ItemClick(Index As Int, Value As Object)
	If Value Is String Then
		If Value = "request" Then
			StartActivity(StockRequest)
		End If
	End If
End Sub

Private Sub CreateRequestStocksRow As Panel
	Dim pnl As Panel
	pnl.Initialize("")
	pnl.Color = Colors.RGB(247, 250, 255)
	pnl.SetLayout(0, 0, clvInventory.AsView.Width, 66dip)

	Dim accent As Panel
	accent.Initialize("")
	accent.Color = Colors.RGB(33, 150, 243)
	pnl.AddView(accent, 10dip, 12dip, 4dip, 42dip)

	Dim lblTitle As Label
	lblTitle.Initialize("")
	lblTitle.Text = "Request Stocks"
	lblTitle.TextSize = 17
	lblTitle.TextColor = Colors.RGB(25, 55, 95)
	lblTitle.Typeface = Typeface.DEFAULT_BOLD
	pnl.AddView(lblTitle, 24dip, 12dip, clvInventory.AsView.Width - 50dip, 24dip)

	Dim lblSubtitle As Label
	lblSubtitle.Initialize("")
	lblSubtitle.Text = "Tap to open the request screen"
	lblSubtitle.TextSize = 12
	lblSubtitle.TextColor = Colors.RGB(96, 125, 139)
	pnl.AddView(lblSubtitle, 24dip, 34dip, clvInventory.AsView.Width - 50dip, 16dip)

	Dim lblChevron As Label
	lblChevron.Initialize("")
	lblChevron.Text = Chr(0x203A)
	lblChevron.TextSize = 26
	lblChevron.Typeface = Typeface.DEFAULT_BOLD
	lblChevron.TextColor = Colors.RGB(33, 150, 243)
	lblChevron.Gravity = Gravity.CENTER
	pnl.AddView(lblChevron, clvInventory.AsView.Width - 40dip, 14dip, 28dip, 30dip)

	Return pnl
End Sub

Private Sub CreateInventoryRow(itemName As String, itemCode As String, unitPrice As Double, assignedStock As Int, usedStock As Int, remainingStock As Int) As Panel
	Dim pnl As Panel
	pnl.Initialize("")
	pnl.Color = Colors.White
	pnl.SetLayout(0, 0, clvInventory.AsView.Width, 96dip)

	Dim lblName As Label
	lblName.Initialize("")
	lblName.Text = itemName
	lblName.TextSize = 16
	lblName.TextColor = Colors.Black
	lblName.Typeface = Typeface.DEFAULT_BOLD
	pnl.AddView(lblName, 12dip, 8dip, clvInventory.AsView.Width - 120dip, 22dip)

	Dim lblPrice As Label
	lblPrice.Initialize("")
	lblPrice.Text = "₱" & NumberFormat2(unitPrice, 1, 2, 2, False)
	lblPrice.TextSize = 14
	lblPrice.TextColor = Colors.RGB(0, 120, 0)
	pnl.AddView(lblPrice, 12dip, 32dip, clvInventory.AsView.Width - 120dip, 20dip)

	Dim lblCode As Label
	lblCode.Initialize("")
	lblCode.Text = "Code: " & itemCode
	lblCode.TextSize = 12
	lblCode.TextColor = Colors.Gray
	pnl.AddView(lblCode, 12dip, 52dip, clvInventory.AsView.Width - 120dip, 16dip)

	Dim stockPanel As Panel
	stockPanel.Initialize("")
	stockPanel.Color = GetStockColor(remainingStock, assignedStock)
	pnl.AddView(stockPanel, clvInventory.AsView.Width - 92dip, 14dip, 80dip, 68dip)

	Dim lblStockTitle As Label
	lblStockTitle.Initialize("")
	lblStockTitle.Text = "Left"
	lblStockTitle.TextSize = 11
	lblStockTitle.TextColor = Colors.White
	lblStockTitle.Gravity = Gravity.CENTER
	stockPanel.AddView(lblStockTitle, 0, 6dip, stockPanel.Width, 16dip)

	Dim lblStockValue As Label
	lblStockValue.Initialize("")
	lblStockValue.Text = "" & remainingStock
	lblStockValue.TextSize = 20
	lblStockValue.TextColor = Colors.White
	lblStockValue.Typeface = Typeface.DEFAULT_BOLD
	lblStockValue.Gravity = Gravity.CENTER
	stockPanel.AddView(lblStockValue, 0, 24dip, stockPanel.Width, 28dip)

	Dim lblStockMeta As Label
	lblStockMeta.Initialize("")
	lblStockMeta.Text = "Used " & usedStock
	lblStockMeta.TextSize = 10
	lblStockMeta.TextColor = Colors.White
	lblStockMeta.Gravity = Gravity.CENTER
	stockPanel.AddView(lblStockMeta, 0, 50dip, stockPanel.Width, 14dip)

	Dim pnlSep As Panel
	pnlSep.Initialize("")
	pnlSep.Color = Colors.RGB(235, 235, 235)
	pnl.AddView(pnlSep, 12dip, 92dip, clvInventory.AsView.Width - 24dip, 1dip)

	Return pnl
End Sub

Private Sub ShowEmptyInventoryMessage
	If clvInventory.IsInitialized = False Then Return

	Dim pnlEmpty As Panel
	pnlEmpty.Initialize("")
	pnlEmpty.Color = Colors.Transparent
	pnlEmpty.SetLayout(0, 0, clvInventory.AsView.Width, 78dip)

	Dim lblEmpty As Label
	lblEmpty.Initialize("")
	lblEmpty.Text = "No products cached. Go to Dashboard and sync first."
	lblEmpty.TextSize = 14
	lblEmpty.TextColor = Colors.Gray
	lblEmpty.Gravity = Gravity.CENTER
	pnlEmpty.AddView(lblEmpty, 0, 18dip, clvInventory.AsView.Width, 32dip)

	clvInventory.Add(pnlEmpty, "empty")
End Sub

Private Sub ShowOrderDetails(orderID As Int)
	Dim cursorOrder As Cursor
	Dim cursorItems As Cursor
	Try
		cursorOrder = Main.SQLProducts.ExecQuery2("SELECT * FROM orders WHERE order_id = ?", Array As String(orderID))
		If cursorOrder.RowCount = 0 Then
			cursorOrder.Close
			ToastMessageShow("Order not found.", False)
			Return
		End If

		cursorOrder.Position = 0

		Dim transactionNumber As String = ""
		If HasColumn("orders", "transaction_number") Then
			transactionNumber = cursorOrder.GetString("transaction_number")
			If transactionNumber = Null Then transactionNumber = ""
		End If

		Dim orderDate As Long = 0
		If HasColumn("orders", "date_created") Then orderDate = cursorOrder.GetLong("date_created")

		Dim totalAmount As Double = 0
		If HasColumn("orders", "total_amount") Then totalAmount = cursorOrder.GetDouble("total_amount")

		Dim orderStatus As String = ""
		If HasColumn("orders", "status") Then
			orderStatus = cursorOrder.GetString("status")
			If orderStatus = Null Then orderStatus = ""
		End If

		Dim isPaid As Boolean = False
		Dim isReceived As Boolean = False
		Dim isBooked As Boolean = False
		If HasColumn("orders", "is_paid") Then
			isPaid = cursorOrder.GetInt("is_paid") = 1
			isReceived = cursorOrder.GetInt("is_received") = 1
			isBooked = cursorOrder.GetInt("is_booked") = 1
			orderStatus = BuildOrderStatusDisplay(isPaid, isReceived, isBooked)
		Else
			orderStatus = GetOrderDisplayStatus(orderID, orderStatus)
		End If

		Dim customerName As String = ""
		Dim customerOwner As String = ""
		Dim customerAddress As String = ""
		If HasColumn("orders", "customer_name") Then
			customerName = cursorOrder.GetString("customer_name")
			If customerName = Null Then customerName = ""
			customerOwner = cursorOrder.GetString("customer_owner")
			If customerOwner = Null Then customerOwner = ""
			customerAddress = cursorOrder.GetString("customer_address")
			If customerAddress = Null Then customerAddress = ""
		End If

		cursorItems = Main.SQLProducts.ExecQuery2( _
			"SELECT oi.product_id, oi.quantity, oi.price, i.item_name " & _
			"FROM order_items oi " & _
			"LEFT JOIN items i ON oi.product_id = i.item_id " & _
			"WHERE oi.order_id = ?", _
			Array As String(orderID))

		Dim itemsText As String = ""
		If cursorItems.RowCount = 0 Then
			itemsText = "(No item lines found)"
		Else
			For i = 0 To cursorItems.RowCount - 1
				cursorItems.Position = i

				Dim itemName As String = cursorItems.GetString("item_name")
				If itemName = Null Or itemName = "" Then itemName = "Item #" & cursorItems.GetInt("product_id")

				Dim quantity As Int = cursorItems.GetInt("quantity")
				Dim price As Double = cursorItems.GetDouble("price")
				Dim lineTotal As Double = price * quantity

				itemsText = itemsText & itemName & CRLF & _
					"₱" & NumberFormat2(price, 1, 2, 2, False) & " × (" & quantity & ") = ₱" & NumberFormat2(lineTotal, 1, 2, 2, False) & CRLF & CRLF
			Next
		End If

		Dim paidLabel As String = IIf(isPaid, "✓ Paid", "✗ Unpaid")
		Dim receivedLabel As String = IIf(isReceived, "✓ Received", "✗ Not Received")
		Dim bookedLabel As String = IIf(isBooked, "✓ Booked", "✗ Not Booked")

		Dim message As String = "Transaction: " & transactionNumber & CRLF & _
			(IIf(customerName <> "", "Customer: " & customerName & CRLF, "")) & _
			(IIf(customerOwner <> "", "Owner: " & customerOwner & CRLF, "")) & _
			(IIf(customerAddress <> "", "Address: " & customerAddress & CRLF, "")) & _
			"Date: " & DateTime.Date(orderDate) & CRLF & _
			paidLabel & "  |  " & receivedLabel & "  |  " & bookedLabel & CRLF & _
			"Total: ₱" & NumberFormat2(totalAmount, 1, 2, 2, False) & CRLF & CRLF & _
			"Items:" & CRLF & itemsText

		cursorOrder.Close
		cursorItems.Close

		Msgbox2Async(message, "Order #" & orderID, "OK", "", "", Null, False)
		Wait For Msgbox_Result (Result As Int)
	Catch
		If cursorOrder.IsInitialized Then cursorOrder.Close
		If cursorItems.IsInitialized Then cursorItems.Close
		Log("ShowOrderDetails error: " & LastException.Message)
		ToastMessageShow("Could not load order details. Please try again.", True)
	End Try
End Sub

Private Sub bttnAddOrder_Click
	' Open customer selection first so chosen customer is attached to the order
	StartActivity(customerSelection)
End Sub

' ======================
' DASHBOARD TAB - FETCH PRODUCTS
' ======================

Private Sub bttnFetchProducts_Click
	If Main.VENDOR_ID <= 0 Then
		ShowFetchErrorMessage("No vendor assigned to current login")
		ToastMessageShow("Please log in again.", True)
		Return
	End If

	SetFetchButtonBusyState(True)
	lblFetchStatus.Text = "Connecting to server..."
	lblFetchStatus.TextColor = Colors.Blue
	' Create a local HttpJob and track it in currentFetchJob so we can release on pause
	Dim fetchJob As HttpJob
	fetchJob.Initialize("FetchProducts", Me)
	currentFetchJob = fetchJob

	Dim fetchUrl As String = Main.API_URL & "API/get_items.php?vendor_id=" & Main.VENDOR_ID
	fetchJob.Download(fetchUrl)

	Wait For (fetchJob) JobDone(jobFetch As HttpJob)

	If jobFetch.Success Then
		Dim response As String = jobFetch.GetString
		If response = "" Or response = Null Then
			ShowFetchErrorMessage("Server returned empty response")
		Else
			ParseAndSaveProductsFromServerResponse(response)
			FetchAssignedStockForLocalCache
		End If
	Else
		ShowFetchErrorMessage("Cannot connect. Check WiFi and server.")
		ToastMessageShow("Network error. Using cached data.", True)
	End If

	' After items are fetched, attempt to fetch & cache customers for offline use
	Dim custJob As HttpJob
	custJob.Initialize("FetchCustomers", Me)
	currentCustomerJob = custJob
	Dim custUrl As String = Main.API_URL & "API/search_customers.php?limit=1000"
	custJob.Download(custUrl)

	Wait For (custJob) JobDone(jobCust As HttpJob)
	If jobCust.Success Then
		Dim custResp As String = jobCust.GetString
		If custResp <> "" And custResp <> Null Then
			ParseAndSaveCustomersFromServerResponse(custResp)
		End If
	Else
		Log("Customer fetch failed: " & jobCust.ErrorMessage)
	End If
	jobCust.Release
	currentCustomerJob = Null

	SetFetchButtonBusyState(False)
	jobFetch.Release
	currentFetchJob = Null
End Sub

Private Sub SetFetchButtonBusyState(isBusy As Boolean)
	If isBusy Then
		bttnFetchProducts.Enabled = False
		bttnFetchProducts.Color = Colors.LightGray
	Else
		bttnFetchProducts.Enabled = True
		bttnFetchProducts.Color = Colors.Blue
	End If
End Sub

Private Sub ParseAndSaveProductsFromServerResponse(response As String)
	Try
		Dim parser As JSONParser
		parser.Initialize(response)
		Dim root As Map = parser.NextObject

		If root.Get("status") <> "success" Then
			ShowFetchErrorMessage("Server returned an error")
			Return
		End If

		Dim items As List = root.Get("data")
		DeleteOldCacheAndSaveFreshProducts(items)

		Main.ITEMS_LAST_SYNC = DateTime.Now
		lblFetchStatus.Text = "✓ Sync completed successfully!"
		lblFetchStatus.TextColor = Colors.RGB(0, 150, 0)
		UpdateDashboardStatusLabels
		ToastMessageShow("Synced " & items.Size & " products", False)

	Catch
		ShowFetchErrorMessage("Failed to read server response: " & LastException.Message)
	End Try
End Sub

Private Sub FetchAssignedStockForLocalCache
	If Main.LoggedInUserID <= 0 Or Main.LoggedInConventionID <= 0 Then Return

	Dim stockJob As HttpJob
	stockJob.Initialize("FetchAssignedStock", Me)
	currentSyncJob = stockJob
	Dim stockUrl As String = Main.API_URL & "API/get_order_taker_stock.php?convention_id=" & Main.LoggedInConventionID & _
		"&user_id=" & Main.LoggedInUserID & _
		"&limit=1000"
	stockJob.Download(stockUrl)

	Wait For (stockJob) JobDone(jobStock As HttpJob)
	If jobStock.Success = False Then
		Log("Assigned stock fetch failed: " & jobStock.ErrorMessage)
	Else
		Try
			Dim parser As JSONParser
			parser.Initialize(jobStock.GetString)
			Dim root As Map = parser.NextObject
			If root.Get("status") <> "success" Then
				Log("Assigned stock fetch returned no success status")
			Else
				Dim rows As List = root.Get("data")
				If rows.IsInitialized Then
					Log("Assigned stock refresh returned " & rows.Size & " row(s)")
					ApplyAssignedStockToLocalItems(rows)
				End If
			End If
		Catch
			Log("FetchAssignedStockForLocalCache error: " & LastException.Message)
		End Try
	End If

	LoadInventoryItemsIntoCLV

	jobStock.Release
	currentSyncJob = Null
End Sub

Private Sub ApplyAssignedStockToLocalItems(rows As List)
	If rows.IsInitialized = False Or rows.Size = 0 Then Return

	Dim pendingUsage As Map = GetPendingLocalStockUsageMap

	Try
		Main.SQLProducts.ExecNonQuery("BEGIN TRANSACTION")
		For Each stockRow As Map In rows
			Dim itemId As Int = 0
			If stockRow.ContainsKey("item_id") And stockRow.Get("item_id") <> Null Then
				itemId = stockRow.Get("item_id")
			End If
			If itemId <= 0 Then Continue

			Dim assignedStock As Int = 0
			If stockRow.ContainsKey("assigned_stock") And stockRow.Get("assigned_stock") <> Null Then
				assignedStock = stockRow.Get("assigned_stock")
			End If

			Dim usedStock As Int = 0
			If stockRow.ContainsKey("used_stock") And stockRow.Get("used_stock") <> Null Then
				usedStock = stockRow.Get("used_stock")
			End If

			Dim pendingUsed As Int = 0
			If pendingUsage.IsInitialized And pendingUsage.ContainsKey(itemId) Then
				pendingUsed = pendingUsage.Get(itemId)
			End If

			Dim remainingStock As Int = 0
			If stockRow.ContainsKey("remaining_stock") And stockRow.Get("remaining_stock") <> Null Then
				remainingStock = stockRow.Get("remaining_stock")
			Else
				remainingStock = assignedStock - usedStock
			End If

			If pendingUsed > 0 Then
				usedStock = usedStock + pendingUsed
				remainingStock = remainingStock - pendingUsed
			End If

			If remainingStock < 0 Then remainingStock = 0

			Main.SQLProducts.ExecNonQuery2( _
				"UPDATE items SET assigned_stock = ?, used_stock = ?, remaining_stock = ? WHERE item_id = ?", _
				Array As Object(assignedStock, usedStock, remainingStock, itemId))
			Log("Stock cache updated for item_id=" & itemId & ": assigned=" & assignedStock & ", used=" & usedStock & ", remaining=" & remainingStock)
		Next
		Main.SQLProducts.ExecNonQuery("COMMIT")
	Catch
		Try
			Main.SQLProducts.ExecNonQuery("ROLLBACK")
		Catch
			Log(LastException.Message)
		End Try
		Log("ApplyAssignedStockToLocalItems error: " & LastException.Message)
	End Try
End Sub

Private Sub GetPendingLocalStockUsageMap As Map
	Dim pendingUsage As Map
	pendingUsage.Initialize

	If Main.SQLProducts.IsInitialized = False Then Return pendingUsage

	Dim rs As ResultSet
	Try
		rs = Main.SQLProducts.ExecQuery2( _
			"SELECT oi.product_id, IFNULL(SUM(oi.quantity), 0) AS pending_qty " & _
			"FROM orders o " & _
			"INNER JOIN order_items oi ON oi.order_id = o.order_id " & _
			"WHERE o.vendor_id = ? AND o.user_id = ? AND IFNULL(o.sync_status, '') NOT IN ('Synced', 'Cancelled') " & _
			"GROUP BY oi.product_id", _
			Array As String(Main.VENDOR_ID, Main.LoggedInUserID))

		Do While rs.NextRow
			pendingUsage.Put(rs.GetInt("product_id"), rs.GetInt("pending_qty"))
		Loop
		rs.Close
	Catch
		If rs.IsInitialized Then rs.Close
		Log("GetPendingLocalStockUsageMap error: " & LastException.Message)
	End Try

	Return pendingUsage
End Sub

Private Sub DeleteOldCacheAndSaveFreshProducts(items As List)
	Dim currentVendor As Int = Main.VENDOR_ID
	If currentVendor <= 0 Then
		Log("Skip cache save: invalid vendor")
		Return
	End If

	' Use a transaction for bulk writes to avoid per-insert commits (much faster and avoids UI blocking)
	Try
		Main.SQLProducts.ExecNonQuery("BEGIN TRANSACTION")
		Main.SQLProducts.ExecNonQuery2("DELETE FROM items WHERE vendor_id = ?", Array As Object(currentVendor))

		For i = 0 To items.Size - 1
			Dim item As Map = items.Get(i)

			Dim barcode As String = ""
			If item.ContainsKey("barcode") And item.Get("barcode") <> Null Then
				barcode = item.Get("barcode")
			End If

			Dim vendorID As Int = currentVendor
			If item.ContainsKey("vendor_id") And item.Get("vendor_id") <> Null Then
				vendorID = item.Get("vendor_id")
			End If

			Main.SQLProducts.ExecNonQuery2( _
				"INSERT OR REPLACE INTO items (item_id, item_code, item_name, unit_price, barcode, vendor_id, is_active) VALUES (?, ?, ?, ?, ?, ?, ?)", _
				Array As Object(item.Get("item_id"), item.Get("item_code"), item.Get("item_name"), item.Get("unit_price"), barcode, vendorID, 1))
		Next

		Main.SQLProducts.ExecNonQuery("COMMIT")
	Catch
		Try
			Main.SQLProducts.ExecNonQuery("ROLLBACK")
		Catch
			Log(LastException.Message)
		End Try
		Log("DeleteOldCacheAndSaveFreshProducts error: " & LastException.Message)
	End Try
End Sub


Private Sub ParseAndSaveCustomersFromServerResponse(response As String)
	Try
		Dim parser As JSONParser
		parser.Initialize(response)
		Dim root As Map = parser.NextObject

		If root.Get("status") <> "success" Then
			Log("Customer fetch returned no success status")
			Return
		End If

		Dim customers As List = root.Get("data")
		If customers.IsInitialized = False Then Return

		' Replace local customer cache using a transaction for bulk writes
		Try
			Main.SQLProducts.ExecNonQuery("BEGIN TRANSACTION")
			Main.SQLProducts.ExecNonQuery("DELETE FROM mst_customers")

			For i = 0 To customers.Size - 1
				Dim c As Map = customers.Get(i)
				Dim cid As Int = 0
				If c.ContainsKey("customer_id") Then cid = c.Get("customer_id")
				Dim code As String = ""
				If c.ContainsKey("customer_code") Then code = c.Get("customer_code")
				Dim name As String = ""
				If c.ContainsKey("customer_name") Then name = c.Get("customer_name")
				Dim owner As String = ""
				If c.ContainsKey("business_owner") Then owner = c.Get("business_owner")
				Dim addr As String = ""
				If c.ContainsKey("address") Then addr = c.Get("address")
				Dim cat As String = ""
				If c.ContainsKey("category") Then cat = c.Get("category")
				Dim branchId As Int = 0
				If c.ContainsKey("branch_id") Then branchId = c.Get("branch_id")

				Main.SQLProducts.ExecNonQuery2( _
					"INSERT OR REPLACE INTO mst_customers (customer_id, customer_code, customer_name, business_owner, address, is_active, branch_id, category) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", _
					Array As Object(cid, code, name, owner, addr, 1, branchId, cat))
			Next

			Main.SQLProducts.ExecNonQuery("COMMIT")
			Log("Cached " & customers.Size & " customers locally")
		Catch
			Try
				Main.SQLProducts.ExecNonQuery("ROLLBACK")
			Catch
				Log(LastException.Message)
			End Try
			Log("ParseAndSaveCustomersFromServerResponse error while saving: " & LastException.Message)
		End Try
	Catch
		Log("ParseAndSaveCustomersFromServerResponse error: " & LastException.Message)
	End Try
End Sub

Private Sub bttnSyncOrdersNow_Click
	SyncNextPendingOrder
End Sub

Private Sub LoadHistoryIntoCustomListView
	If clvContentHistory.IsInitialized = False Then Return
	If Main.SQLProducts.IsInitialized = False Then
		ToastMessageShow("Local database is not ready.", True)
		Return
	End If

	clvContentHistory.Clear
	If pnlContentHistoryPagination.IsInitialized Then pnlContentHistoryPagination.Visible = True

	Dim rowW As Int = clvContentHistory.AsView.Width
	If rowW <= 0 Then rowW = 100%x

	' Query distinct sync dates with summary (paginated)
	Dim totalDateGroups As Int = GetHistoryDateGroupCount
	totalHistoryPages = Ceil(totalDateGroups / HISTORY_PAGE_SIZE)
	If totalHistoryPages < 1 Then totalHistoryPages = 1
	If currentHistoryPage < 1 Then currentHistoryPage = 1
	If currentHistoryPage > totalHistoryPages Then currentHistoryPage = totalHistoryPages

	RefreshHistoryPaginationBar

	Dim dateOffset As Int = (currentHistoryPage - 1) * HISTORY_PAGE_SIZE
	Dim rsGroups As ResultSet = Main.SQLProducts.ExecQuery2( _
		"SELECT DATE(date_created / 1000, 'unixepoch', 'localtime') AS order_date, " & _
		"MIN(date_created) AS first_tick, " & _
		"COUNT(*) AS order_count, " & _
		"IFNULL(SUM(total_amount), 0) AS date_total " & _
		"FROM orders " & _
		"WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Synced' " & _
		"GROUP BY order_date ORDER BY order_date DESC " & _
		"LIMIT ? OFFSET ?", _
		Array As String(Main.VENDOR_ID, Main.LoggedInUserID, HISTORY_PAGE_SIZE, dateOffset))

	If rsGroups.RowCount = 0 Then
		rsGroups.Close
		Dim pnlEmpty As Panel
		pnlEmpty.Initialize("")
		pnlEmpty.Color = Colors.Transparent
		Dim lblEmpty As Label
		lblEmpty.Initialize("")
		lblEmpty.Text = "No synced orders yet."
		lblEmpty.TextSize = 16
		lblEmpty.TextColor = Colors.Gray
		lblEmpty.Gravity = Gravity.CENTER
		pnlEmpty.AddView(lblEmpty, 0, 0, rowW, 200dip)
		clvContentHistory.Add(pnlEmpty, 200dip)
		Return
	End If

	Do While rsGroups.NextRow
		Dim syncDate As String = rsGroups.GetString("order_date")
		Dim firstTick As Long = rsGroups.GetLong("first_tick")
		Dim orderCount As Int = rsGroups.GetInt("order_count")
		Dim dateTotal As Double = rsGroups.GetDouble("date_total")
		Dim isExpanded As Boolean = expandedDates.ContainsKey(syncDate)

		' === Date Group Header Card ===
		Dim headerH As Int = 62dip
		Dim pnlHeader As Panel
		pnlHeader.Initialize("")
		Dim cdHeader As ColorDrawable
		cdHeader.Initialize(Colors.White, 10dip)
		pnlHeader.Background = cdHeader
		pnlHeader.SetLayout(0, 0, rowW, headerH)

		Dim arrow As String
		If isExpanded Then arrow = "▲ " Else arrow = "▼ "

		Dim lblDate As Label
		lblDate.Initialize("")
		lblDate.Text = FormatDateHeader(firstTick)
		lblDate.TextSize = 15
		lblDate.TextColor = Colors.RGB(30, 30, 30)
		lblDate.Typeface = Typeface.DEFAULT_BOLD
		lblDate.Gravity = Gravity.LEFT
		pnlHeader.AddView(lblDate, 14dip, 8dip, rowW - 60dip, 24dip)

		Dim lblArrow As Label
		lblArrow.Initialize("")
		lblArrow.Text = arrow
		lblArrow.TextSize = 14
		lblArrow.TextColor = Colors.RGB(120, 120, 120)
		lblArrow.Gravity = Gravity.CENTER
		pnlHeader.AddView(lblArrow, rowW - 44dip, 8dip, 30dip, 24dip)

		Dim lblSummary As Label
		lblSummary.Initialize("")
		lblSummary.Text = orderCount & " Orders  —  ₱" & NumberFormat2(dateTotal, 1, 2, 2, False)
		lblSummary.TextSize = 12
		lblSummary.TextColor = Colors.RGB(107, 114, 128)
		lblSummary.Gravity = Gravity.LEFT
		pnlHeader.AddView(lblSummary, 14dip, 34dip, rowW - 60dip, 20dip)

		' Tag = "date:" prefix so click handler knows this is a date header
		clvContentHistory.Add(pnlHeader, "date:" & syncDate)

		' === Expanded: show order rows for this date ===
		If isExpanded Then
			Dim rsOrders As ResultSet = Main.SQLProducts.ExecQuery2( _
				"SELECT * FROM orders " & _
				"WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Synced' " & _
				"AND DATE(date_created / 1000, 'unixepoch', 'localtime') = ? " & _
				"ORDER BY date_created DESC", _
				Array As String(Main.VENDOR_ID, Main.LoggedInUserID, syncDate))

			Do While rsOrders.NextRow
				Dim orderId As Int = rsOrders.GetInt("order_id")
				Dim totalAmount As Double = rsOrders.GetDouble("total_amount")
				Dim syncStatus As String = rsOrders.GetString("sync_status")
				Dim displayStatus As String = GetOrderSyncStatusLabel(syncStatus)

				Dim receiptNumber As String = ""
				If HasColumn("orders", "transaction_number") Then
					receiptNumber = rsOrders.GetString("transaction_number")
					If receiptNumber = Null Then receiptNumber = ""
				End If

				Dim customerName As String = ""
				If HasColumn("orders", "customer_name") Then
					customerName = rsOrders.GetString("customer_name")
					If customerName = Null Then customerName = ""
				End If

				Dim card As Panel
				card.Initialize("")
				card.Color = Colors.RGB(250, 250, 252)
				card.SetLayout(0, 0, rowW, 100dip)

				Dim lblTitle As Label
				lblTitle.Initialize("")
				lblTitle.Text = "Order #" & orderId
				lblTitle.TextSize = 15
				lblTitle.TextColor = Colors.Black
				lblTitle.Typeface = Typeface.DEFAULT_BOLD
				card.AddView(lblTitle, 24dip, 8dip, rowW * 0.55, 22dip)

				Dim lblTransaction As Label
				lblTransaction.Initialize("")
				lblTransaction.Text = "Transaction: " & receiptNumber
				lblTransaction.TextSize = 11
				lblTransaction.TextColor = Colors.Gray
				card.AddView(lblTransaction, 24dip, 30dip, rowW * 0.75, 16dip)

				Dim lblCustomer As Label
				lblCustomer.Initialize("")
				lblCustomer.Text = "Customer: " & customerName
				lblCustomer.TextSize = 11
				lblCustomer.TextColor = Colors.RGB(33, 150, 243)
				card.AddView(lblCustomer, 24dip, 48dip, rowW * 0.75, 16dip)

				Dim lblAmount As Label
				lblAmount.Initialize("")
				lblAmount.Text = "Total: ₱" & NumberFormat2(totalAmount, 1, 2, 2, False)
				lblAmount.TextSize = 13
				lblAmount.TextColor = Colors.RGB(0, 122, 0)
				card.AddView(lblAmount, 24dip, 68dip, rowW * 0.6, 20dip)

				Dim lblStatus As Label
				lblStatus.Initialize("")
				lblStatus.Text = displayStatus
				lblStatus.TextSize = 11
				lblStatus.TextColor = Colors.White
				Dim cdStatus As ColorDrawable
				cdStatus.Initialize(GetOrderSyncStatusColor(syncStatus), 4dip)
				lblStatus.Background = cdStatus
				lblStatus.Gravity = Gravity.CENTER
				card.AddView(lblStatus, rowW - 100dip, 10dip, 70dip, 22dip)

				' Left indent line to show nesting
				Dim pnlIndent As Panel
				pnlIndent.Initialize("")
				pnlIndent.Color = Colors.RGB(33, 150, 243)
				card.AddView(pnlIndent, 10dip, 6dip, 3dip, 88dip)

				' Tag = "order:" prefix + order ID
				clvContentHistory.Add(card, "order:" & orderId)
			Loop
			rsOrders.Close
		End If
	Loop
	rsGroups.Close
End Sub

Private Sub clvContentHistory_ItemClick(Index As Int, Value As Object)
	Dim tag As String = Value
	If tag.StartsWith("date:") Then
		Dim syncDate As String = tag.SubString("date:".Length)
		If expandedDates.ContainsKey(syncDate) Then
			expandedDates.Remove(syncDate)
		Else
			expandedDates.Put(syncDate, True)
		End If
		LoadHistoryIntoCustomListView
	Else If tag.StartsWith("order:") Then
		Dim orderID As Int = tag.SubString("order:".Length)
		ShowOrderDetails(orderID)
	End If
End Sub

Private Sub SetupHistoryPagination
	If clvContentHistory.IsInitialized = False Then Return
	If pnlContentHistoryPagination.IsInitialized = False Then Return

	pnlContentHistoryPagination.RemoveAllViews
	pnlContentHistoryPagination.Visible = True

	Dim barHeight As Int = pnlContentHistoryPagination.Height
	If barHeight <= 0 Then barHeight = 48dip

	bttnHistoryPrev.Initialize("bttnHistoryPrev")
	bttnHistoryPrev.Text = "Prev"
	bttnHistoryPrev.Enabled = False
	pnlContentHistoryPagination.AddView(bttnHistoryPrev, 8dip, 6dip, 64dip, barHeight - 12dip)

	lblHistoryPage.Initialize("")
	lblHistoryPage.Text = "1 / 1"
	lblHistoryPage.TextColor = Colors.Gray
	lblHistoryPage.TextSize = 14
	lblHistoryPage.Gravity = Gravity.CENTER
	pnlContentHistoryPagination.AddView(lblHistoryPage, 76dip, 6dip, pnlContentHistoryPagination.Width - 152dip, barHeight - 12dip)

	bttnHistoryNext.Initialize("bttnHistoryNext")
	bttnHistoryNext.Text = "Next"
	bttnHistoryNext.Enabled = False
	pnlContentHistoryPagination.AddView(bttnHistoryNext, pnlContentHistoryPagination.Width - 72dip, 6dip, 64dip, barHeight - 12dip)

	Dim historyList As View = clvContentHistory.AsView
	historyList.SetLayout(historyList.Left, historyList.Top, historyList.Width, pnlContentHistory.Height - barHeight - historyList.Top)
End Sub

Private Sub RefreshHistoryPaginationBar
	If lblHistoryPage.IsInitialized = False Then Return

	If totalHistoryPages < 1 Then totalHistoryPages = 1
	If currentHistoryPage < 1 Then currentHistoryPage = 1
	If currentHistoryPage > totalHistoryPages Then currentHistoryPage = totalHistoryPages

	lblHistoryPage.Text = currentHistoryPage & " / " & totalHistoryPages
	bttnHistoryPrev.Enabled = currentHistoryPage > 1
	bttnHistoryNext.Enabled = currentHistoryPage < totalHistoryPages
End Sub

Private Sub GetHistoryDateGroupCount As Int
	Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
		"SELECT COUNT(DISTINCT DATE(date_created / 1000, 'unixepoch', 'localtime')) AS total " & _
		"FROM orders WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Synced'", _
		Array As String(Main.VENDOR_ID, Main.LoggedInUserID))
	Dim total As Int = 0
	If rs.NextRow Then total = rs.GetInt("total")
	rs.Close
	Return total
End Sub

Private Sub bttnHistoryPrev_Click
	If currentHistoryPage <= 1 Then Return
	currentHistoryPage = currentHistoryPage - 1
	LoadHistoryIntoCustomListView
End Sub

Private Sub bttnHistoryNext_Click
	If currentHistoryPage >= totalHistoryPages Then Return
	currentHistoryPage = currentHistoryPage + 1
	LoadHistoryIntoCustomListView
End Sub

Private Sub GetOrderSyncStatusLabel(syncStatus As String) As String
	If syncStatus = "Holding" Or syncStatus = "" Then
		Return "Holding"
	Else If syncStatus = "Synced" Then
		Return "Synced"
	Else If syncStatus = "Cancelled" Then
		Return "Cancelled"
	Else
		Return syncStatus.ToUpperCase
	End If
End Sub

Private Sub GetOrderSyncStatusColor(syncStatus As String) As Int
	If syncStatus = "Synced" Then
		Return Colors.RGB(0, 150, 0)
	Else If syncStatus = "Cancelled" Then
		Return Colors.RGB(244, 67, 54)
	Else
		Return Colors.Gray
	End If
End Sub

Private Sub FormatDateHeader(dateTicks As Long) As String
	' Format date as header: "Today", "Yesterday", or "Monday, April 7, 2026"
	Dim today As Long = DateTime.DateParse(DateTime.Date(DateTime.Now))
	Dim yesterday As Long = today - DateTime.TicksPerDay
	Dim orderDate As Long = DateTime.DateParse(DateTime.Date(dateTicks))
	
	If orderDate = today Then
		Return "Today"
	Else If orderDate = yesterday Then
		Return "Yesterday"
	Else
		' Format as "Monday, April 7, 2026"
		Dim oldDateFormat As String = DateTime.DateFormat
		Dim oldTimeFormat As String = DateTime.TimeFormat
		DateTime.DateFormat = "EEEE, MMMM d, yyyy"
		Dim formattedDate As String = DateTime.Date(dateTicks)
		DateTime.DateFormat = oldDateFormat
		DateTime.TimeFormat = oldTimeFormat
		Return formattedDate
	End If
End Sub

Private Sub SyncNextPendingOrder
	If Main.SQLProducts.IsInitialized = False Then
		ToastMessageShow("Local database is not ready.", True)
		Return
	End If

	If syncOrdersCompletedCount < 0 Then syncOrdersCompletedCount = 0

	Dim rsOrder As ResultSet = Main.SQLProducts.ExecQuery("SELECT * FROM orders WHERE IFNULL(sync_status, '') NOT IN ('Synced', 'Cancelled') ORDER BY date_created ASC LIMIT 1")
	If rsOrder.RowCount = 0 Then
		rsOrder.Close
		If syncOrdersCompletedCount > 0 Then
			ToastMessageShow("Successfully synced.", False)
		Else
			ToastMessageShow("No pending orders to sync.", False)
		End If
		syncOrdersCompletedCount = 0
		LoadOrdersIntoList
		UpdateDashboardStatusLabels
		DrawWeeklySalesChart
		DrawOrderStatusPieChart
		Return
	End If

	rsOrder.Position = 0
	Dim localOrderID As Int = rsOrder.GetInt("order_id")
	Dim payload As String = BuildOrderSyncPayload(rsOrder)
	rsOrder.Close

	Dim syncJob As HttpJob
	syncJob.Initialize("SyncOrder", Me)
	currentSyncJob = syncJob
	syncJob.PostString(Main.API_URL & "API/sync_order.php", payload)

	Wait For (syncJob) JobDone(jobSync As HttpJob)
	If jobSync.Success Then
		Try
			Dim parser As JSONParser
			parser.Initialize(jobSync.GetString)
			Dim root As Map = parser.NextObject
			Dim status As String = root.Get("status")
			If status = "success" Then
				Main.SQLProducts.ExecNonQuery2("UPDATE orders SET sync_status = 'Synced', synced_at = ? WHERE order_id = ?", Array As Object(DateTime.Now, localOrderID))
				syncOrdersCompletedCount = syncOrdersCompletedCount + 1
				LoadOrdersIntoList
				LoadHistoryIntoCustomListView
				FetchAssignedStockForLocalCache
				UpdateDashboardStatusLabels
				DrawWeeklySalesChart
				DrawOrderStatusPieChart
				jobSync.Release
				currentSyncJob = Null
				SyncNextPendingOrder
				Return
			Else
				syncOrdersCompletedCount = 0
				ToastMessageShow("Sync failed: " & root.Get("message"), True)
			End If
		Catch
			syncOrdersCompletedCount = 0
			ToastMessageShow("Sync response parse failed: " & LastException.Message, True)
		End Try
	Else
		syncOrdersCompletedCount = 0
		ToastMessageShow("Sync network error: " & jobSync.ErrorMessage, True)
	End If

	jobSync.Release
	currentSyncJob = Null
End Sub

Private Sub BuildOrderSyncPayload(rsOrder As ResultSet) As String
	Dim localOrderID As Int = rsOrder.GetInt("order_id")
	Dim createdAt As Long = DateTime.Now
	Try
		createdAt = rsOrder.GetLong("date_created")
	Catch
		createdAt = DateTime.Now
	End Try
	If createdAt <= 0 Then createdAt = DateTime.Now

	Dim itemCount As Int = 0
	If HasColumn("orders", "item_count") Then itemCount = rsOrder.GetInt("item_count")
	If itemCount <= 0 Then itemCount = GetLocalOrderItemCount(localOrderID)

	Dim bookingValue As Int = 0
	Dim prepaidValue As Int = 0
	Dim isPaidValue As Int = 0
	Dim isReceivedValue As Int = 0
	Dim isBookedValue As Int = 0
	If HasColumn("orders", "is_paid") Then
		isPaidValue = rsOrder.GetInt("is_paid")
		isReceivedValue = rsOrder.GetInt("is_received")
		isBookedValue = rsOrder.GetInt("is_booked")
		prepaidValue = isPaidValue
		bookingValue = isBookedValue
	Else
		If HasColumn("orders", "booking") Then bookingValue = rsOrder.GetInt("booking")
		If HasColumn("orders", "prepaid") Then prepaidValue = rsOrder.GetInt("prepaid")
	End If

	Dim customerCode As String = "0"
	If HasColumn("orders", "customer_code") Then customerCode = rsOrder.GetString("customer_code")
	If customerCode = Null Or customerCode.Trim = "" Then customerCode = "0"

	Dim orderHeader As Map
	orderHeader.Initialize
	orderHeader.Put("vendor_id", rsOrder.GetInt("vendor_id"))
	orderHeader.Put("user_id", rsOrder.GetInt("user_id"))
	orderHeader.Put("convention_id", GetOrderConventionID(rsOrder))
	orderHeader.Put("order_date", FormatSqlDate(createdAt))
	orderHeader.Put("order_dt", FormatSqlDateTime(createdAt))
	orderHeader.Put("item_count", itemCount)
	orderHeader.Put("total_amount", rsOrder.GetDouble("total_amount"))
	orderHeader.Put("booking", bookingValue)
	orderHeader.Put("customer_code", customerCode)
	orderHeader.Put("status", "O")
	orderHeader.Put("transaction_number", rsOrder.GetString("transaction_number"))
	orderHeader.Put("device_id", rsOrder.GetString("device_id"))
	orderHeader.Put("prepaid", prepaidValue)
	orderHeader.Put("is_paid", isPaidValue)
	orderHeader.Put("is_received", isReceivedValue)
	orderHeader.Put("is_booked", isBookedValue)

	Dim details As List
	details.Initialize

	Dim rsItems As ResultSet = Main.SQLProducts.ExecQuery2( _
		"SELECT oi.product_id, oi.quantity, oi.price " & _
		"FROM order_items oi " & _
		"WHERE oi.order_id = ? ORDER BY oi.order_item_id", _
		Array As String(localOrderID))

	Do While rsItems.NextRow
		Dim itemMap As Map
		itemMap.Initialize
		Dim quantity As Int = rsItems.GetInt("quantity")
		Dim unitPrice As Double = rsItems.GetDouble("price")

		itemMap.Put("item_id", rsItems.GetInt("product_id"))
		itemMap.Put("quantity", quantity)
		itemMap.Put("unit_price", unitPrice)
		details.Add(itemMap)
	Loop
	rsItems.Close

	Dim root As Map
	root.Initialize
	root.Put("order_header", orderHeader)
	root.Put("order_details", details)

	Dim gen As JSONGenerator
	gen.Initialize(root)
	Return gen.ToString
End Sub

Private Sub FormatSqlDate(ticks As Long) As String
	Dim oldDateFormat As String = DateTime.DateFormat
	DateTime.DateFormat = "yyyy-MM-dd"
	Dim value As String = DateTime.Date(ticks)
	DateTime.DateFormat = oldDateFormat
	Return value
End Sub

Private Sub FormatSqlDateTime(ticks As Long) As String
	Dim oldDateFormat As String = DateTime.DateFormat
	Dim oldTimeFormat As String = DateTime.TimeFormat
	DateTime.DateFormat = "yyyy-MM-dd"
	DateTime.TimeFormat = "HH:mm:ss"
	Dim value As String = DateTime.Date(ticks) & " " & DateTime.Time(ticks)
	DateTime.DateFormat = oldDateFormat
	DateTime.TimeFormat = oldTimeFormat
	Return value
End Sub

Private Sub GetLocalOrderItemCount(orderId As Int) As Int
	Dim totalQuantity As Int = 0
	Dim rs As ResultSet = Main.SQLProducts.ExecQuery2("SELECT IFNULL(SUM(quantity), 0) AS total_qty FROM order_items WHERE order_id = ?", Array As String(orderId))
	If rs.NextRow Then
		totalQuantity = rs.GetInt("total_qty")
	End If
	rs.Close
	Return totalQuantity
End Sub

Private Sub GetOrderConventionID(rsOrder As ResultSet) As Int
	If HasColumn("orders", "convention_id") Then
		Dim conventionId As Int = rsOrder.GetInt("convention_id")
		If conventionId > 0 Then Return conventionId
	End If
	Return Main.LoggedInConventionID
End Sub

Private Sub ShowFetchErrorMessage(errorMessage As String)
	lblFetchStatus.Text = "✗ " & errorMessage
	lblFetchStatus.TextColor = Colors.Red
End Sub

Private Sub BuildOrderStatusDisplay(isPaid As Boolean, isReceived As Boolean, isBooked As Boolean) As String
	Dim parts As List
	parts.Initialize
	If isPaid Then parts.Add("Paid") Else parts.Add("Unpaid")
	If isReceived Then parts.Add("Received")
	If isBooked Then parts.Add("Booked")
	Dim result As String = ""
	For i = 0 To parts.Size - 1
		If i > 0 Then result = result & ", "
		result = result & parts.Get(i)
	Next
	Return result
End Sub

Private Sub GetOrderDisplayStatus(orderID As Int, fallbackStatus As String) As String
	' Try reading boolean columns first
	Try
		If HasColumn("orders", "is_paid") Then
			Dim rsStatus As ResultSet = Main.SQLProducts.ExecQuery2( _
				"SELECT is_paid, is_received, is_booked FROM orders WHERE order_id = ?", _
				Array As String(orderID))
			If rsStatus.NextRow Then
				Dim result As String = BuildOrderStatusDisplay( _
					rsStatus.GetInt("is_paid") = 1, _
					rsStatus.GetInt("is_received") = 1, _
					rsStatus.GetInt("is_booked") = 1)
				rsStatus.Close
				If result <> "" Then Return result
			End If
			rsStatus.Close
		End If
	Catch
		Log("GetOrderDisplayStatus boolean path error: " & LastException.Message)
	End Try

	If fallbackStatus <> "" And fallbackStatus <> "Pending" Then
		Return fallbackStatus
	End If

	Try
		Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT fulfillment_status FROM order_items WHERE order_id = ? LIMIT 1", _
			Array As String(orderID))
		If rs.NextRow Then
			Dim fulfillmentStatus As String = rs.GetString("fulfillment_status")
			If fulfillmentStatus <> Null And fulfillmentStatus <> "" Then
				rs.Close
				Return fulfillmentStatus
			End If
		End If
		rs.Close
	Catch
		Log("GetOrderDisplayStatus error: " & LastException.Message)
	End Try

	Return fallbackStatus
End Sub

' ======================
' INVENTORY TAB
' ======================

Private Sub GetStockColor(remainingStock As Int, assignedStock As Int) As Int
	If assignedStock <= 0 Then Return Colors.Gray
	If remainingStock <= 0 Then Return Colors.RGB(198, 40, 40)
	If remainingStock <= 5 Then Return Colors.RGB(230, 126, 34)
	Return Colors.RGB(46, 125, 50)
End Sub

Private Sub HasColumnValue(rs As ResultSet, columnName As String) As Boolean
	Try
		rs.GetString(columnName)
		Return True
	Catch
		Return False
	End Try
End Sub

' ======================
' DASHBOARD TAB - STATUS
' ======================

Private Sub UpdateDashboardStatusLabels
	EnsureLocalSchema

	Dim cachedProductCount As Int = 0
	Dim rs As ResultSet
	Try
		rs = Main.SQLProducts.ExecQuery2( _
            "SELECT COUNT(*) as count FROM items WHERE is_active = 1 AND vendor_id = ?", _
            Array As String(Main.VENDOR_ID))
		If rs.NextRow Then
			cachedProductCount = rs.GetInt("count")
		End If
		rs.Close
	Catch
		If rs.IsInitialized Then rs.Close
		cachedProductCount = 0
	End Try

	If cachedProductCount > 0 Then
		If Main.ITEMS_LAST_SYNC > 0 Then
			lblCacheInfo.Text = "📦 " & cachedProductCount & " products cached | Last sync: " & FormatTimeAgo(Main.ITEMS_LAST_SYNC)
			lblCacheInfo.TextColor = Colors.RGB(0, 100, 0)
			lblFetchStatus.Text = "✓ Ready to take orders"
			lblFetchStatus.TextColor = Colors.RGB(0, 150, 0)
		Else
			lblCacheInfo.Text = "📦 " & cachedProductCount & " products cached (sync time unknown)"
			lblCacheInfo.TextColor = Colors.Gray
		End If
	Else
		lblCacheInfo.Text = "⚠ No products synced yet"
		lblCacheInfo.TextColor = Colors.RGB(200, 100, 0)
		lblFetchStatus.Text = "Tap button above to sync products"
		lblFetchStatus.TextColor = Colors.Gray
	End If

	' pending order count is shown in history summary labels (no toast)
	UpdateDashboardSummaryLabels
End Sub

Private Sub FormatTimeAgo(syncTimestamp As Long) As String
	Dim minutesAgo As Long = (DateTime.Now - syncTimestamp) / DateTime.TicksPerMinute

	If minutesAgo < 1 Then
		Return "Just now"
	Else If minutesAgo < 60 Then
		Return minutesAgo & " minutes ago"
	Else If minutesAgo < 1440 Then
		Return (minutesAgo / 60) & " hours ago"
	Else
		Return (minutesAgo / 1440) & " days ago"
	End If
End Sub


Private Sub UpdateDashboardSummaryLabels
	Dim todayStart As Long = DateTime.DateParse(DateTime.Date(DateTime.Now))
	Dim todayEnd As Long = todayStart + DateTime.TicksPerDay

	Dim rs As ResultSet

	rs = Main.SQLProducts.ExecQuery2( _
			"SELECT COUNT(*) AS total_orders, IFNULL(SUM(total_amount), 0) AS total_sales " & _
			"FROM orders " & _
			"WHERE vendor_id = ? AND user_id = ? AND date_created >= ? AND date_created < ? AND IFNULL(sync_status, '') = 'Synced'", _
			Array As String(Main.VENDOR_ID, Main.LoggedInUserID, todayStart, todayEnd))

	If rs.NextRow Then
		lblTodaysOrders.Text = "Today's Orders" & CRLF & rs.GetInt("total_orders")
		lblTodaySales.Text = "Today's Sales" & CRLF & "₱" & NumberFormat2(rs.GetDouble("total_sales"), 1, 2, 2, False)
	End If
	rs.Close

	rs = Main.SQLProducts.ExecQuery( _
			"SELECT COUNT(*) AS pending_count " & _
			"FROM orders " & _
			"WHERE IFNULL(sync_status, '') NOT IN ('Synced', 'Cancelled')")

	If rs.NextRow Then
		Dim pendingCount As Int = rs.GetInt("pending_count")
		lblPendingSync.Text = "Pending Sync" & CRLF & pendingCount
		If pendingCount > 0 Then
			lblPendingSync.TextColor = Colors.RGB(234, 88, 12)
		Else
			lblPendingSync.TextColor = Colors.RGB(22, 163, 74)
		End If
	End If
	rs.Close

	Dim rsSummary As ResultSet
	Try
		rsSummary = Main.SQLProducts.ExecQuery2( _
			"SELECT COUNT(*) AS total_orders, IFNULL(SUM(total_amount), 0) AS total_sales, IFNULL(SUM(item_count), 0) AS total_items " & _
			"FROM orders " & _
			"WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Synced'", _
			Array As String(Main.VENDOR_ID, Main.LoggedInUserID))

		If rsSummary.NextRow Then
			Dim totalSyncedOrders As Int = rsSummary.GetInt("total_orders")
			Dim totalSyncedAmount As Double = rsSummary.GetDouble("total_sales")
			Dim totalSyncedItems As Int = rsSummary.GetInt("total_items")
			
			Log("DEBUG: Summary query returned - Orders: " & totalSyncedOrders & ", Amount: " & totalSyncedAmount & ", Items: " & totalSyncedItems)
			
			' Always try to set the text, initialize if needed
			Try
				lblHistoryTotalOrderSync.Text = "Total Orders" & CRLF & "Synced: " & totalSyncedOrders
				Log("DEBUG: Set lblHistoryTotalOrderSync to: " & lblHistoryTotalOrderSync.Text)
			Catch
				Log("DEBUG: Failed to set lblHistoryTotalOrderSync: " & LastException.Message)
			End Try
			
			Try
				Dim formattedAmount As String = NumberFormat2(totalSyncedAmount, 1, 2, 2, False)
				lblHistoryTotalAmountSynced.Text = "Total Amount" & CRLF & "Synced: ₱" & formattedAmount
				Log("DEBUG: Set lblHistoryTotalAmountSynced to: " & lblHistoryTotalAmountSynced.Text)
			Catch
				Log("DEBUG: Failed to set lblHistoryTotalAmountSynced: " & LastException.Message)
				Log("DEBUG: totalSyncedAmount value is: " & totalSyncedAmount)
			End Try
			
			Try
				lblHistoryTotalItemsSynced.Text = "Total Items" & CRLF & "Synced: " & totalSyncedItems
				Log("DEBUG: Set lblHistoryTotalItemsSynced to: " & lblHistoryTotalItemsSynced.Text)
			Catch
				Log("DEBUG: Failed to set lblHistoryTotalItemsSynced: " & LastException.Message)
			End Try
		End If
		If rsSummary.IsInitialized Then rsSummary.Close
	Catch
		Log("UpdateDashboardSummaryLabels error: " & LastException.Message)
		If rsSummary.IsInitialized Then rsSummary.Close
	End Try
End Sub

' ======================
' DASHBOARD TAB - CARD LAYOUT
' ======================

Private Sub SetupDashboardCards
	pnlContentDash.Color = Colors.RGB(241, 245, 249)

	Dim M As Int = 12dip
	Dim W As Int = pnlContentDash.Width - (M * 2)
	Dim S As Int = 6dip
	Dim R As Float = 12dip
	Dim P As Int = 14dip

	Dim statusH As Int = 68dip
	Dim statsH As Int = 60dip
	Dim totalsH As Int = 36dip
	Dim buttonsH As Int = 100dip
	Dim totalFixed As Int = statusH + statsH + totalsH + buttonsH + (S * 7)
	Dim chartAreaH As Int = pnlContentDash.Height - totalFixed
	Dim lineChartH As Int = chartAreaH * 2 / 5
	Dim pieChartH As Int = chartAreaH - lineChartH

	Dim Y As Int = S

	' === Card 1: Status Info ===
	AddCardToPanel(pnlContentDash, M, Y, W, statusH, R)

	lblCacheInfo.TextSize = 14
	lblCacheInfo.Gravity = Gravity.LEFT
	lblCacheInfo.SetLayout(M + P, Y + 8dip, W - (P * 2), 26dip)
	lblCacheInfo.BringToFront

	lblFetchStatus.TextSize = 14
	lblFetchStatus.Gravity = Gravity.LEFT
	lblFetchStatus.SetLayout(M + P, Y + 36dip, W - (P * 2), 26dip)
	lblFetchStatus.BringToFront

	Y = Y + statusH + S

	' === Card 2: Stats Row (3 columns) ===
	AddCardToPanel(pnlContentDash, M, Y, W, statsH, R)

	Dim colW As Int = W / 3

	lblTodaysOrders.Gravity = Gravity.CENTER
	lblTodaysOrders.TextSize = 12
	lblTodaysOrders.TextColor = Colors.RGB(55, 65, 81)
	lblTodaysOrders.SetLayout(M, Y + 4dip, colW, statsH - 8dip)
	lblTodaysOrders.BringToFront

	lblTodaySales.Gravity = Gravity.CENTER
	lblTodaySales.TextSize = 12
	lblTodaySales.TextColor = Colors.RGB(55, 65, 81)
	lblTodaySales.SetLayout(M + colW, Y + 4dip, colW, statsH - 8dip)
	lblTodaySales.BringToFront

	lblPendingSync.Gravity = Gravity.CENTER
	lblPendingSync.TextSize = 12
	lblPendingSync.TextColor = Colors.RGB(55, 65, 81)
	lblPendingSync.SetLayout(M + (colW * 2), Y + 4dip, colW, statsH - 8dip)
	lblPendingSync.BringToFront

	Dim div1 As Panel : div1.Initialize("")
	div1.Color = Colors.RGB(229, 231, 235)
	pnlContentDash.AddView(div1, M + colW, Y + 12dip, 1dip, statsH - 24dip)
	
	Dim div2 As Panel : div2.Initialize("")
	div2.Color = Colors.RGB(229, 231, 235)
	pnlContentDash.AddView(div2, M + (colW * 2), Y + 12dip, 1dip, statsH - 24dip)
	
	Y = Y + statsH + S

	' === Card 3: Weekly Sales Line Chart ===
	AddCardToPanel(pnlContentDash, M, Y, W, lineChartH, R)

	If pnllineChart.IsInitialized Then
		pnllineChart.SetLayout(M + 4dip, Y + 4dip, W - 8dip, lineChartH - 8dip)
		pnllineChart.BringToFront
	End If

	Y = Y + lineChartH + S

	' === Card 4: Order Status Pie Chart ===
	AddCardToPanel(pnlContentDash, M, Y, W, pieChartH, R)

	If pnlPiechart.IsInitialized Then
		pnlPiechart.SetLayout(M + 4dip, Y + 4dip, W - 8dip, pieChartH - 8dip)
		pnlPiechart.BringToFront
	End If

	Y = Y + pieChartH + S

	' === Card 5: Synced Totals Row ===
	AddCardToPanel(pnlContentDash, M, Y, W, totalsH, R)

	Dim totColW As Int = W / 3

	Try
		If lblHistoryTotalOrderSync.IsInitialized Then
			lblHistoryTotalOrderSync.Gravity = Gravity.CENTER
			lblHistoryTotalOrderSync.TextSize = 11
			lblHistoryTotalOrderSync.TextColor = Colors.RGB(75, 85, 99)
			lblHistoryTotalOrderSync.SetLayout(M, Y + 2dip, totColW, totalsH - 4dip)
			lblHistoryTotalOrderSync.BringToFront
		End If
	Catch
		Log("SetupDashboardCards: lblHistoryTotalOrderSync error")
	End Try

	Try
		If lblHistoryTotalAmountSynced.IsInitialized Then
			lblHistoryTotalAmountSynced.Gravity = Gravity.CENTER
			lblHistoryTotalAmountSynced.TextSize = 11
			lblHistoryTotalAmountSynced.TextColor = Colors.RGB(75, 85, 99)
			lblHistoryTotalAmountSynced.SetLayout(M + totColW, Y + 2dip, totColW, totalsH - 4dip)
			lblHistoryTotalAmountSynced.BringToFront
		End If
	Catch
		Log("SetupDashboardCards: lblHistoryTotalAmountSynced error")
	End Try

	Try
		If lblHistoryTotalItemsSynced.IsInitialized Then
			lblHistoryTotalItemsSynced.Gravity = Gravity.CENTER
			lblHistoryTotalItemsSynced.TextSize = 11
			lblHistoryTotalItemsSynced.TextColor = Colors.RGB(75, 85, 99)
			lblHistoryTotalItemsSynced.SetLayout(M + (totColW * 2), Y + 2dip, totColW, totalsH - 4dip)
			lblHistoryTotalItemsSynced.BringToFront
		End If
	Catch
		Log("SetupDashboardCards: lblHistoryTotalItemsSynced error")
	End Try

	Y = Y + totalsH + S

	' === Card 6: Action Buttons ===
	AddCardToPanel(pnlContentDash, M, Y, W, buttonsH, R)

	Dim cdFetch As ColorDrawable
	cdFetch.Initialize(Colors.RGB(33, 150, 243), 8dip)
	bttnFetchProducts.Background = cdFetch
	bttnFetchProducts.TextColor = Colors.White
	bttnFetchProducts.SetLayout(M + P, Y + 10dip, W - (P * 2), 42dip)
	bttnFetchProducts.BringToFront

	Dim cdSync As ColorDrawable
	cdSync.Initialize(Colors.RGB(240, 240, 240), 8dip)
	bttnSyncOrdersNow.Background = cdSync
	bttnSyncOrdersNow.TextColor = Colors.RGB(55, 65, 81)
	bttnSyncOrdersNow.SetLayout(M + P, Y + 56dip, W - (P * 2), 42dip)
	bttnSyncOrdersNow.BringToFront
End Sub

Private Sub AddCardToPanel(parent As Panel, left As Int, top As Int, width As Int, height As Int, radius As Float)
	Dim pnlBorder As Panel
	pnlBorder.Initialize("")
	Dim cdBorder As ColorDrawable
	cdBorder.Initialize(Colors.RGB(80, 80, 80), radius)
	pnlBorder.Background = cdBorder
	parent.AddView(pnlBorder, left, top, width, height)

	Dim pnlFill As Panel
	pnlFill.Initialize("")
	Dim cdFill As ColorDrawable
	cdFill.Initialize(Colors.White, radius)
	pnlFill.Background = cdFill
	pnlBorder.AddView(pnlFill, 1dip, 1dip, width - 2dip, height - 2dip)
End Sub

'search bar
Private Sub etContentSearchOrder_TextChanged (Old As String, New As String)
	currentOrdersPage = 1
	LoadOrdersIntoList
End Sub

' ======================
' DASHBOARD TAB - LINE CHART
' ======================

Private Sub DrawWeeklySalesChart
	' Check if panel exists and is initialized
	Try
		If pnllineChart.IsInitialized = False Or pnllineChart = Null Then Return
	Catch
		Log("DrawWeeklySalesChart skipped: pnllineChart not ready")
		Return
	End Try
	
	' All possible day labels for reference
	Dim allDayLabels() As String = Array As String("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
	
	' Calculate sales for each day of the week
	Dim today As Long = DateTime.DateParse(DateTime.Date(DateTime.Now))
	Dim dayOfWeek As Int = DateTime.GetDayOfWeek(today)
	' dayOfWeek: 1=Sunday, 2=Monday, ..., 7=Saturday
	' Convert to: 0=Monday, 1=Tuesday, ..., 6=Sunday
	Dim adjustedDay As Int = dayOfWeek - 2
	If adjustedDay < 0 Then adjustedDay = adjustedDay + 7
	
	' Calculate Monday of current week
	Dim startOfWeek As Long = today - adjustedDay * DateTime.TicksPerDay
	
	' Calculate how many days to display (Monday to today, inclusive)
	Dim daysToDisplay As Int = adjustedDay + 1
	
	' Create arrays for only the days we need to display
	Dim dayLabels(daysToDisplay) As String
	Dim dailySales(daysToDisplay) As Float
	
	' Copy only the relevant day labels
	For i = 0 To daysToDisplay - 1
		dayLabels(i) = allDayLabels(i)
	Next
	
	Dim maxSales As Float = 0
	
	' Query sales for each day from Monday to today
	For i = 0 To daysToDisplay - 1
		Dim dayStart As Long = startOfWeek + i * DateTime.TicksPerDay
		Dim dayEnd As Long = dayStart + DateTime.TicksPerDay
		
		Dim rs As ResultSet
		Try
			rs = Main.SQLProducts.ExecQuery2( _
				"SELECT IFNULL(SUM(total_amount), 0) AS daily_sales " & _
				"FROM orders " & _
				"WHERE vendor_id = ? AND user_id = ? AND date_created >= ? AND date_created < ? AND IFNULL(sync_status, '') = 'Synced'", _
				Array As String(Main.VENDOR_ID, Main.LoggedInUserID, dayStart, dayEnd))
			
			If rs.NextRow Then
				Dim sales As Double = rs.GetDouble("daily_sales")
				dailySales(i) = sales
				If sales > maxSales Then maxSales = sales
			End If
			rs.Close
		Catch
			If rs.IsInitialized Then rs.Close
			dailySales(i) = 0
		End Try
	Next
	
	' Set default scale if no sales
	If maxSales = 0 Then maxSales = 1000
	
	' Create canvas for drawing
	Dim cvs As Canvas
	cvs.Initialize(pnllineChart)
	cvs.DrawColor(Colors.White)
	
	' Chart dimensions — leave room for day labels at the bottom
	Dim chartTop As Int = 28dip
	Dim chartBottom As Int = pnllineChart.Height - 32dip
	Dim chartLeft As Int = 50dip
	Dim chartRight As Int = pnllineChart.Width - 10dip
	If pnllineChart.Height < 150dip Then
		chartTop = 22dip
		chartBottom = pnllineChart.Height - 28dip
		chartLeft = 44dip
	End If
	Dim chartWidth As Int = chartRight - chartLeft
	Dim chartHeight As Int = chartBottom - chartTop

	' Draw title with currency indicator
	cvs.DrawText("Weekly Sales Trend (₱)", pnllineChart.Width / 2, 18dip, Typeface.DEFAULT_BOLD, 14, Colors.RGB(0, 102, 204), "CENTER")

	' Draw axes
	cvs.DrawLine(chartLeft, chartTop, chartLeft, chartBottom, Colors.RGB(180, 180, 180), 1dip)
	cvs.DrawLine(chartLeft, chartBottom, chartRight, chartBottom, Colors.RGB(180, 180, 180), 1dip)

	' Draw grid lines and Y-axis labels
	Dim gridLines As Int = 4
	For j = 0 To gridLines
		Dim yValue As Float = maxSales * (gridLines - j) / gridLines
		Dim yPixel As Int = chartTop + (j * chartHeight / gridLines)

		cvs.DrawLine(chartLeft, yPixel, chartRight, yPixel, Colors.RGB(230, 230, 230), 1dip)

		Dim labelText As String = NumberFormat(yValue, 1, 0)
		cvs.DrawText(labelText, chartLeft - 6dip, yPixel + 4dip, Typeface.DEFAULT, 10, Colors.Gray, "RIGHT")
	Next

	' Draw data points and lines
	Dim pointRadius As Int = 4dip
	For i = 0 To daysToDisplay - 1
		Dim xPixel As Int = chartLeft + (i * chartWidth / Max(daysToDisplay - 1, 1))
		Dim yPixel As Int = chartBottom - (dailySales(i) / maxSales) * chartHeight

		cvs.DrawCircle(xPixel, yPixel, pointRadius, Colors.RGB(33, 150, 243), True, 0)

		If i < daysToDisplay - 1 Then
			Dim nextXPixel As Int = chartLeft + ((i + 1) * chartWidth / Max(daysToDisplay - 1, 1))
			Dim nextYPixel As Int = chartBottom - (dailySales(i + 1) / maxSales) * chartHeight
			cvs.DrawLine(xPixel, yPixel, nextXPixel, nextYPixel, Colors.RGB(33, 150, 243), 2dip)
		End If

		cvs.DrawText(dayLabels(i), xPixel, chartBottom + 14dip, Typeface.DEFAULT, 10, Colors.Gray, "CENTER")
	Next
	
	pnllineChart.Invalidate
End Sub

Private Sub DrawOrderStatusPieChart
	Try
		If pnlPiechart.IsInitialized = False Or pnlPiechart = Null Then
			Log("DrawOrderStatusPieChart skipped: pnlPiechart not initialized")
			Return
		End If
	Catch
		Log("DrawOrderStatusPieChart error: pnlPiechart check failed - " & LastException.Message)
		Return
	End Try
	
	' Query order counts by status
	Dim completedCount As Int = 0
	Dim pendingCount As Int = 0
	Dim cancelledCount As Int = 0
	
	' Get Synced/Completed orders
	Try
		Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT COUNT(*) AS cnt FROM orders WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Synced'", _
			Array As String(Main.VENDOR_ID, Main.LoggedInUserID))
		If rs.NextRow Then completedCount = rs.GetInt("cnt")
		rs.Close
	Catch
		Log("Error counting synced orders: " & LastException.Message)
	End Try
	
	' Get Pending/Holding orders (awaiting sync)
	Try
		Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT COUNT(*) AS cnt FROM orders WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Holding'", _
			Array As String(Main.VENDOR_ID, Main.LoggedInUserID))
		If rs.NextRow Then pendingCount = rs.GetInt("cnt")
		rs.Close
	Catch
		Log("Error counting holding orders: " & LastException.Message)
	End Try
	
	' Get Cancelled orders (holding orders that were cancelled by the user)
	Try
		Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT COUNT(*) AS cnt FROM orders WHERE vendor_id = ? AND user_id = ? AND IFNULL(sync_status, '') = 'Cancelled'", _
			Array As String(Main.VENDOR_ID, Main.LoggedInUserID))
		If rs.NextRow Then cancelledCount = rs.GetInt("cnt")
		rs.Close
	Catch
		Log("Error counting cancelled orders: " & LastException.Message)
	End Try
	
	' Build pie chart data - if all counts are zero, don't draw
	If completedCount = 0 And pendingCount = 0 And cancelledCount = 0 Then
		Log("No order status data to display in pie chart")
		Return
	End If
	
	' Create pie data structure - initialize fields first
	Dim PD As PieData
	
	' Initialize List and Canvas BEFORE assigning to PieData fields
	Dim itemsList As List
	itemsList.Initialize
	Dim cvs As Canvas
	cvs.Initialize(pnlPiechart)
	
	' Now assign to PieData
	PD.Items = itemsList
	PD.Canvas = cvs
	PD.Target = pnlPiechart
	PD.GapDegrees = 5
	PD.LegendTextSize = 13
	PD.LegendBackColor = Colors.White
	
	' Add pie items
	Charts.AddPieItem(PD, "Completed", completedCount, Colors.RGB(76, 175, 80)) ' Green
	Charts.AddPieItem(PD, "Pending", pendingCount, Colors.RGB(255, 152, 0))     ' Orange
	Charts.AddPieItem(PD, "Cancelled", cancelledCount, Colors.RGB(244, 67, 54)) ' Red
	
	' Draw the pie chart
	Charts.DrawPie(PD, Colors.White, False)
	
	' Draw title above pie chart
	cvs.DrawText("Order Status Weekly Overview", pnlPiechart.Width / 2, 13dip, Typeface.DEFAULT_BOLD, 16, Colors.RGB(0, 102, 204), "CENTER")
	
	' Draw legend manually below the pie chart
	DrawPieChartLegend(cvs, pnlPiechart, completedCount, pendingCount, cancelledCount)
	
	pnlPiechart.Invalidate
End Sub

Private Sub DrawPieChartLegend(cvs As Canvas, panel As Panel, completed As Int, pending As Int, cancelled As Int)
	Dim spacing As Int = 24dip
	Dim boxSize As Int = 13dip
	Dim textSize As Int = 12

	If panel.Height < 200dip Then
		spacing = 18dip
		boxSize = 11dip
		textSize = 10
	End If

	Dim legendH As Int = spacing * 3
	Dim legendStartX As Int = 18dip
	Dim legendStartY As Int = panel.Height - legendH - 6dip
	Dim rect As Rect

	rect.Initialize(legendStartX, legendStartY, legendStartX + boxSize, legendStartY + boxSize)
	cvs.DrawRect(rect, Colors.RGB(76, 175, 80), True, 0)
	cvs.DrawText("Completed " & completed, legendStartX + boxSize + 8dip, legendStartY + 3dip, Typeface.DEFAULT, textSize, Colors.Black, "LEFT")

	rect.Initialize(legendStartX, legendStartY + spacing, legendStartX + boxSize, legendStartY + spacing + boxSize)
	cvs.DrawRect(rect, Colors.RGB(255, 152, 0), True, 0)
	cvs.DrawText("Pending " & pending, legendStartX + boxSize + 8dip, legendStartY + spacing + 3dip, Typeface.DEFAULT, textSize, Colors.Black, "LEFT")

	rect.Initialize(legendStartX, legendStartY + spacing * 2, legendStartX + boxSize, legendStartY + spacing * 2 + boxSize)
	cvs.DrawRect(rect, Colors.RGB(244, 67, 54), True, 0)
	cvs.DrawText("Cancelled " & cancelled, legendStartX + boxSize + 8dip, legendStartY + spacing * 2 + 3dip, Typeface.DEFAULT, textSize, Colors.Black, "LEFT")
End Sub


