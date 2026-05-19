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
End Sub

Sub Globals
	Private pnlroot As Panel
	Private lblBack As Label
	Private lblTitle As Label
	Private lblSubtitle As Label
	Private lblRefresh As Label
	Private lblStatus As Label
	Private clvSyncedOrders As CustomListView
	Private currentLoadJob As HttpJob
	Private ordersRows As List
End Sub

Sub Activity_Create(FirstTime As Boolean)
	Activity.LoadLayout("supervisorsyncedorders")
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	If lblSubtitle.IsInitialized Then
		lblSubtitle.Text = "Viewing: " & Main.SelectedOrderTakerFullName & " (@" & Main.SelectedOrderTakerLoginName & ")"
	End If
	If lblTitle.IsInitialized Then
		lblTitle.Text = "Supervisor View"
	End If
	If lblRefresh.IsInitialized Then
		lblRefresh.Text = "Refresh"
	End If
	If lblStatus.IsInitialized Then
		lblStatus.Text = "Loading synced orders..."
	End If
	ordersRows.Initialize
	LoadSyncedOrders
End Sub

Sub Activity_Resume
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	If ordersRows.IsInitialized = False Or ordersRows.Size = 0 Then
		LoadSyncedOrders
	End If
End Sub

Sub Activity_Pause(UserClosed As Boolean)
	If currentLoadJob <> Null Then
		Try
			If currentLoadJob.IsInitialized Then currentLoadJob.Release
		Catch
			Log(LastException.Message)
		End Try
		currentLoadJob = Null
	End If
End Sub

Private Sub LoadSyncedOrders
	If Main.SelectedOrderTakerUserID <= 0 Then
		lblStatus.Text = "No selected order taker."
		ToastMessageShow("Select an order taker first.", True)
		Return
	End If

	lblStatus.Text = "Loading synced orders..."
	clvSyncedOrders.Clear

	Dim job As HttpJob
	job.Initialize("load_synced_orders", Me)
	currentLoadJob = job
	Dim url As String = Main.API_URL & "API/get_synced_orders.php?user_id=" & Main.SelectedOrderTakerUserID & _
		"&vendor_id=" & Main.SelectedOrderTakerVendorID & _
		"&limit=200"
	job.Download(url)

	Wait For (job) JobDone(job As HttpJob)
	If job.Success = False Then
		lblStatus.Text = "Unable to load synced orders."
		ToastMessageShow("Unable to load synced orders.", True)
		job.Release
		currentLoadJob = Null
		Return
	End If

	Try
		Dim parser As JSONParser
		parser.Initialize(job.GetString)
		Dim root As Map = parser.NextObject
		If root.Get("status") <> "success" Then
			Dim message As String = "Failed to load synced orders."
			If root.ContainsKey("message") And root.Get("message") <> Null Then message = root.Get("message")
			lblStatus.Text = message
			ToastMessageShow(message, True)
			job.Release
			currentLoadJob = Null
			Return
		End If

		ordersRows.Initialize
		Dim data As List = root.Get("data")
		For Each row As Map In data
			ordersRows.Add(row)
		Next

		BuildOrderList
		If ordersRows.Size = 0 Then
			lblStatus.Text = "No synced orders found."
		Else
			lblStatus.Text = ordersRows.Size & " synced order(s) loaded"
		End If
	Catch
		lblStatus.Text = "Invalid response from server."
		ToastMessageShow("Invalid response from server.", True)
	End Try

	job.Release
	currentLoadJob = Null
End Sub

Private Sub BuildOrderList
	clvSyncedOrders.Clear

	For Each orderRow As Map In ordersRows
		Dim orderId As Int = GetIntValue(orderRow, "order_id")
		Dim card As Panel
		card.Initialize("")
		card.Color = Colors.White
		card.SetLayout(0, 0, clvSyncedOrders.AsView.Width, 92dip)

		Dim lblOrder As Label
		lblOrder.Initialize("")
		lblOrder.Text = "Order #" & orderId
		lblOrder.TextSize = 16
		lblOrder.Typeface = Typeface.DEFAULT_BOLD
		lblOrder.TextColor = Colors.Black
		card.AddView(lblOrder, 12dip, 8dip, 50%x, 22dip)

		Dim lblTxn As Label
		lblTxn.Initialize("")
		lblTxn.Text = "Txn: " & GetStringValue(orderRow, "transaction_number") & "  |  Device: " & GetStringValue(orderRow, "device_id")
		lblTxn.TextSize = 12
		lblTxn.TextColor = Colors.Gray
		card.AddView(lblTxn, 12dip, 32dip, 62%x, 18dip)

		Dim lblMeta As Label
		lblMeta.Initialize("")
		lblMeta.Text = GetStringValue(orderRow, "order_date") & "  •  Status: " & GetStringValue(orderRow, "status") & "  •  ₱" & NumberFormat2(GetDoubleValue(orderRow, "total_amount"), 1, 2, 2, False)
		lblMeta.TextSize = 12
		lblMeta.TextColor = Colors.RGB(33, 150, 243)
		card.AddView(lblMeta, 12dip, 54dip, 72%x, 18dip)

		Dim lblSync As Label
		lblSync.Initialize("")
		lblSync.Text = GetStringValue(orderRow, "status")
		lblSync.TextSize = 12
		lblSync.TextColor = Colors.White
		lblSync.Gravity = Gravity.CENTER
		lblSync.Color = Colors.RGB(76, 175, 80)
		card.AddView(lblSync, card.Width - 96dip, 10dip, 82dip, 24dip)

		clvSyncedOrders.Add(card, orderId)
	Next
End Sub

Private Sub clvSyncedOrders_ItemClick(Index As Int, Value As Object)
	Dim orderId As Int = Value
	ShowOrderDetails(orderId)
End Sub

Private Sub ShowOrderDetails(orderId As Int)
	Dim job As HttpJob
	job.Initialize("load_order_details", Me)
	job.Download(Main.API_URL & "API/get_order.php?order_id=" & orderId)

	Wait For (job) JobDone(job As HttpJob)
	If job.Success = False Then
		ToastMessageShow("Unable to load order details.", True)
		job.Release
		Return
	End If

	Try
		Dim parser As JSONParser
		parser.Initialize(job.GetString)
		Dim root As Map = parser.NextObject
		If root.Get("success") <> True Then
			Dim message As String = "Order not found."
			If root.ContainsKey("message") And root.Get("message") <> Null Then message = root.Get("message")
			ToastMessageShow(message, False)
			job.Release
			Return
		End If

		Dim data As Map = root.Get("data")
		Dim details As List = Null
		If root.ContainsKey("details") And root.Get("details") <> Null Then details = root.Get("details")

		Dim sb As StringBuilder
		sb.Initialize
		sb.Append("Order #" & GetIntValue(data, "order_id") & CRLF)
		sb.Append("Transaction: " & GetStringValue(data, "transaction_number") & CRLF)
		sb.Append("Device: " & GetStringValue(data, "device_id") & CRLF)
		sb.Append("Date: " & GetStringValue(data, "order_date") & CRLF)
		sb.Append("Status: " & GetStringValue(data, "status") & CRLF)
		sb.Append("Total: ₱" & NumberFormat2(GetDoubleValue(data, "total_amount"), 1, 2, 2, False) & CRLF & CRLF)
		sb.Append("Items:" & CRLF)

		If details.IsInitialized And details.Size > 0 Then
			For Each itemRow As Map In details
				sb.Append("- " & GetStringValue(itemRow, "item_name") & " x " & GetDoubleValue(itemRow, "quantity") & " @ ₱" & NumberFormat2(GetDoubleValue(itemRow, "selling_price"), 1, 2, 2, False) & CRLF)
			Next
		Else
			sb.Append("No item details available." & CRLF)
		End If

		Msgbox2Async(sb.ToString, "Order #" & orderId, "OK", "", "", Null, False)
		Wait For Msgbox_Result (Result As Int)
	Catch
		ToastMessageShow("Failed to parse order details.", True)
	End Try

	job.Release
End Sub

Private Sub lblRefresh_Click
	LoadSyncedOrders
End Sub

Private Sub btnStock_Click
	If Main.SelectedOrderTakerUserID <= 0 Then
		ToastMessageShow("Select an order taker first.", True)
		Return
	End If
	StartActivity(SupervisorStockAssignment)
	Activity.Finish
End Sub

Private Sub lblBack_Click
	StartActivity(SupervisorOrderTakerSelection)
	Activity.Finish
End Sub

Private Sub GetStringValue(source As Map, key As String) As String
	If source.IsInitialized = False Then Return ""
	If source.ContainsKey(key) = False Then Return ""
	If source.Get(key) = Null Then Return ""
	Return source.Get(key)
End Sub

Private Sub GetIntValue(source As Map, key As String) As Int
	If source.IsInitialized = False Then Return 0
	If source.ContainsKey(key) = False Then Return 0
	If source.Get(key) = Null Then Return 0
	Return source.Get(key)
End Sub

Private Sub GetDoubleValue(source As Map, key As String) As Double
	If source.IsInitialized = False Then Return 0
	If source.ContainsKey(key) = False Then Return 0
	If source.Get(key) = Null Then Return 0
	Return source.Get(key)
End Sub