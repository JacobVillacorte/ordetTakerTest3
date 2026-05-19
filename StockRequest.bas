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
	Private pnlStockRequests As Panel
	Private lblBack As Label
	Private lblRefresh As Label
	Private lblTitle As Label
	Private lblStatus As Label
	Private clvRequestItems As CustomListView
	Private btnSubmit As Button
	Private btnClear As Button
	Private currentLoadJob As HttpJob
	Private currentItems As List
	Private stockRowsByItemId As Map
	Private qtyEditByItemId As Map
	Private requestUserId As Int
	Private requestVendorId As Int
	Private isLoadingRequests As Boolean
	Private Const MAX_REQUEST_QTY_PER_ITEM As Int = 100
End Sub

Sub Activity_Create(FirstTime As Boolean)
	Activity.Color = Colors.RGB(245, 247, 250)
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If

	currentLoadJob = Null
	isLoadingRequests = False
	currentItems.Initialize
	stockRowsByItemId.Initialize
	qtyEditByItemId.Initialize

	Activity.LoadLayout("StockRequest")
	If lblTitle.IsInitialized Then lblTitle.Text = "Request Stocks"
	If lblStatus.IsInitialized Then lblStatus.Text = "Loading inventory..."
	UpdateRequestSubmitState
	LoadRequestData
End Sub

Sub Activity_Resume
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	UpdateRequestSubmitState
	If isLoadingRequests Then Return
	If currentItems.IsInitialized = False Or currentItems.Size = 0 Then
		LoadRequestData
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

Private Sub LoadRequestData
	If isLoadingRequests Then Return

	If Main.SQLProducts.IsInitialized = False Then
		lblStatus.Text = "Local database is not ready."
		ToastMessageShow("Sync inventory first.", True)
		isLoadingRequests = False
		Return
	End If

	requestUserId = GetRequestUserId
	requestVendorId = GetRequestVendorId

	If requestUserId <= 0 Or requestVendorId <= 0 Then
		lblStatus.Text = "Missing stock assignment context."
		ToastMessageShow("No order taker/vendor context found.", True)
		isLoadingRequests = False
		Return
	End If

	isLoadingRequests = True
	lblStatus.Text = "Loading inventory..."
	clvRequestItems.Clear
	currentItems.Initialize
	stockRowsByItemId.Initialize
	qtyEditByItemId.Initialize

	Try
		EnsureLocalSchema

		Dim rs As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT * FROM items WHERE is_active = 1 AND vendor_id = ? ORDER BY item_name", _
			Array As String(requestVendorId))

		If rs.RowCount = 0 Then
			rs.Close
			isLoadingRequests = False
			ShowEmptyRequestMessage("No products are cached for this vendor. Sync first.")
			Return
		End If

		Do While rs.NextRow
			Dim itemData As Map
			itemData.Initialize
			itemData.Put("item_id", rs.GetInt("item_id"))
			itemData.Put("item_name", rs.GetString("item_name"))
			itemData.Put("item_code", rs.GetString("item_code"))
			itemData.Put("unit_price", rs.GetDouble("unit_price"))
			itemData.Put("assigned_stock", GetColumnInt(rs, "assigned_stock"))
			itemData.Put("used_stock", GetColumnInt(rs, "used_stock"))
			itemData.Put("remaining_stock", GetColumnInt(rs, "remaining_stock"))
			currentItems.Add(itemData)
		Loop
		rs.Close

		RenderRequestList
	Catch
		Log("LoadRequestData error: " & LastException.Message)
		isLoadingRequests = False
		lblStatus.Text = "Unable to load inventory."
		ShowEmptyRequestMessage("Unable to load inventory.")
	End Try

	isLoadingRequests = False
End Sub

Private Sub RenderRequestList
	clvRequestItems.Clear

	For Each itemData As Map In currentItems
		Dim itemId As Int = itemData.Get("item_id")
		clvRequestItems.Add(CreateRequestRow(itemData), itemId)
	Next

	If currentItems.Size = 0 Then
		ShowEmptyRequestMessage("No items found for this vendor.")
	Else
		lblStatus.Text = currentItems.Size & " item(s) ready"
	End If
End Sub

Private Sub CreateRequestRow(itemData As Map) As Panel
	Dim itemId As Int = itemData.Get("item_id")
	Dim itemName As String = itemData.Get("item_name")
	Dim itemCode As String = itemData.Get("item_code")
	Dim unitPrice As Double = itemData.Get("unit_price")
	Dim rowWidth As Int = GetRequestRowWidth

	Dim pnl As Panel
	pnl.Initialize("")
	pnl.Color = Colors.White
	pnl.SetLayout(0, 0, rowWidth, 128dip)

	Dim lblName As Label
	lblName.Initialize("")
	lblName.Text = itemName
	lblName.TextSize = 16
	lblName.Typeface = Typeface.DEFAULT_BOLD
	lblName.TextColor = Colors.Black
	pnl.AddView(lblName, 12dip, 8dip, rowWidth - 120dip, 22dip)

	Dim lblPrice As Label
	lblPrice.Initialize("")
	lblPrice.Text = "₱" & NumberFormat2(unitPrice, 1, 2, 2, False)
	lblPrice.TextSize = 14
	lblPrice.TextColor = Colors.RGB(0, 120, 0)
	pnl.AddView(lblPrice, 12dip, 32dip, rowWidth - 120dip, 20dip)

	Dim lblCode As Label
	lblCode.Initialize("")
	lblCode.Text = "Code: " & itemCode
	lblCode.TextSize = 12
	lblCode.TextColor = Colors.Gray
	pnl.AddView(lblCode, 12dip, 52dip, rowWidth - 120dip, 16dip)

	Dim qtyPanel As Panel
	qtyPanel.Initialize("")
	qtyPanel.Color = Colors.Transparent
	pnl.AddView(qtyPanel, rowWidth - 126dip, 28dip, 110dip, 44dip)

	Dim btnMinus As Label
	btnMinus.Initialize("btnQtyMinus")
	btnMinus.Text = "−"
	btnMinus.Tag = itemId
	btnMinus.TextColor = Colors.White
	btnMinus.TextSize = 26
	btnMinus.Typeface = Typeface.DEFAULT_BOLD
	btnMinus.Color = Colors.RGB(96, 125, 139)
	btnMinus.Gravity = Gravity.CENTER
	qtyPanel.AddView(btnMinus, 0dip, 0dip, 32dip, 32dip)

	Dim etQty As EditText
	etQty.Initialize("")
	etQty.Text = "0"
	etQty.Tag = itemId
	etQty.TextSize = 16
	etQty.TextColor = Colors.Black
	etQty.Color = Colors.White
	etQty.Gravity = Gravity.CENTER
	etQty.SingleLine = True
	qtyEditByItemId.Put(itemId, etQty)
	qtyPanel.AddView(etQty, 34dip, 0dip, 38dip, 32dip)

	Dim btnPlus As Label
	btnPlus.Initialize("btnQtyPlus")
	btnPlus.Text = "+"
	btnPlus.Tag = itemId
	btnPlus.TextColor = Colors.White
	btnPlus.TextSize = 26
	btnPlus.Typeface = Typeface.DEFAULT_BOLD
	btnPlus.Color = Colors.RGB(33, 150, 243)
	btnPlus.Gravity = Gravity.CENTER
	qtyPanel.AddView(btnPlus, 74dip, 0dip, 32dip, 32dip)

	Dim lblLimit As Label
	lblLimit.Initialize("")
	lblLimit.Text = "Max " & MAX_REQUEST_QTY_PER_ITEM
	lblLimit.TextSize = 9
	lblLimit.TextColor = Colors.Gray
	lblLimit.Gravity = Gravity.CENTER
	pnl.AddView(lblLimit, rowWidth - 126dip, 62dip, 110dip, 12dip)

	Dim pnlSep As Panel
	pnlSep.Initialize("")
	pnlSep.Color = Colors.RGB(235, 235, 235)
	pnl.AddView(pnlSep, 12dip, 124dip, rowWidth - 24dip, 1dip)

	Return pnl
End Sub

Private Sub btnQtyPlus_Click
	Dim viewSender As View = Sender
	If viewSender.Tag = Null Then Return
	AdjustQty(viewSender.Tag, 1)
End Sub

Private Sub btnQtyMinus_Click
	Dim viewSender As View = Sender
	If viewSender.Tag = Null Then Return
	AdjustQty(viewSender.Tag, -1)
End Sub

Private Sub AdjustQty(itemId As Int, delta As Int)
	If qtyEditByItemId.ContainsKey(itemId) = False Then Return
	Dim et As EditText = qtyEditByItemId.Get(itemId)
	Dim currentQty As Int = ParseQty(et.Text)
	Dim newQty As Int = currentQty + delta
	If newQty < 0 Then newQty = 0
	If newQty > MAX_REQUEST_QTY_PER_ITEM Then newQty = MAX_REQUEST_QTY_PER_ITEM
	et.Text = "" & newQty
End Sub

Private Sub btnSubmit_Click
	If IsDeviceOnline = False Then
		ToastMessageShow("You must be online to submit stock requests.", True)
		lblStatus.Text = "Offline - stock requests are disabled."
		UpdateRequestSubmitState
		Return
	End If

	Dim requests As List
	requests.Initialize

	Dim summary As String = ""
	For Each itemData As Map In currentItems
		Dim itemId As Int = itemData.Get("item_id")
		If qtyEditByItemId.ContainsKey(itemId) = False Then Continue

		Dim et As EditText = qtyEditByItemId.Get(itemId)
		Dim requestQty As Int = ParseQty(et.Text)
		If requestQty <= 0 Then Continue

		If requestQty > MAX_REQUEST_QTY_PER_ITEM Then
			requestQty = MAX_REQUEST_QTY_PER_ITEM
			et.Text = "" & requestQty
		End If

		Dim requestRow As Map
		requestRow.Initialize
		requestRow.Put("item_id", itemId)
		requestRow.Put("requested_qty", requestQty)
		requestRow.Put("item_name", itemData.Get("item_name"))
		requests.Add(requestRow)

		summary = summary & itemData.Get("item_name") & " x " & requestQty & CRLF
	Next

	If requests.Size = 0 Then
		ToastMessageShow("Enter at least one request quantity.", False)
		Return
	End If

	Dim message As String = "Submit these stock requests?" & CRLF & CRLF & summary & CRLF & _
		"Max per item: " & MAX_REQUEST_QTY_PER_ITEM
	Msgbox2Async(message, "Confirm Request", "Confirm", "", "Back", Null, False)
	Wait For Msgbox_Result (Result As Int)
	If Result <> DialogResponse.POSITIVE Then Return

	SubmitRequests(requests)
End Sub

Private Sub SubmitRequests(requests As List)
	If Main.LoggedInConventionID <= 0 Then
		ToastMessageShow("Missing convention context.", True)
		Return
	End If

	If IsDeviceOnline = False Then
		ToastMessageShow("You must be online to submit stock requests.", True)
		lblStatus.Text = "Offline - stock requests are disabled."
		UpdateRequestSubmitState
		Return
	End If

	Dim payload As Map
	payload.Initialize
	payload.Put("convention_id", Main.LoggedInConventionID)
	payload.Put("user_id", requestUserId)
	payload.Put("vendor_id", requestVendorId)
	payload.Put("device_id", Main.DEVICE_ID)
	payload.Put("status", "pending")
	payload.Put("max_request_qty", MAX_REQUEST_QTY_PER_ITEM)
	payload.Put("items", requests)

	Dim gen As JSONGenerator
	gen.Initialize(payload)

	Dim job As HttpJob
	job.Initialize("save_stock_request", Me)
	currentLoadJob = job
	job.PostString(Main.API_URL & "API/save_stock_request.php", gen.ToString)
	job.GetRequest.SetContentType("application/json")

	Wait For (job) JobDone(jobSave As HttpJob)
	If jobSave.Success = False Then
		ToastMessageShow("Unable to submit stock request.", True)
		jobSave.Release
		currentLoadJob = Null
		Return
	End If

	Try
		Dim parser As JSONParser
		parser.Initialize(jobSave.GetString)
		Dim root As Map = parser.NextObject
		If root.Get("status") <> "success" Then
			ToastMessageShow(GetStringValue(root, "message"), True)
			jobSave.Release
			currentLoadJob = Null
			Return
		End If

		ToastMessageShow("Stock request submitted.", False)
		jobSave.Release
		currentLoadJob = Null
		LoadRequestData
	Catch
		Log("SubmitRequests error: " & LastException.Message)
		ToastMessageShow("Invalid response while saving request.", True)
	End Try
End Sub

Private Sub UpdateRequestSubmitState
	If btnSubmit.IsInitialized = False Then Return

	Dim online As Boolean = IsDeviceOnline
	btnSubmit.Enabled = online
	If online Then
		btnSubmit.Color = Colors.RGB(33, 150, 243)
	Else
		btnSubmit.Color = Colors.RGB(180, 180, 180)
	End If
End Sub

Private Sub btnClear_Click
	For Each itemData As Map In currentItems
		Dim itemId As Int = itemData.Get("item_id")
		If qtyEditByItemId.ContainsKey(itemId) Then
			Dim et As EditText = qtyEditByItemId.Get(itemId)
			et.Text = "0"
		End If
	Next
End Sub

Private Sub lblRefresh_Click
	LoadRequestData
End Sub

Private Sub lblBack_Click
	Activity.Finish
End Sub

Private Sub ShowEmptyRequestMessage(message As String)
	clvRequestItems.Clear
	Dim rowWidth As Int = GetRequestRowWidth
	Dim pnlEmpty As Panel
	pnlEmpty.Initialize("")
	pnlEmpty.Color = Colors.Transparent
	pnlEmpty.SetLayout(0, 0, rowWidth, 120dip)

	Dim lblEmpty As Label
	lblEmpty.Initialize("")
	lblEmpty.Text = message
	lblEmpty.TextSize = 15
	lblEmpty.TextColor = Colors.Gray
	lblEmpty.Gravity = Gravity.CENTER
	pnlEmpty.AddView(lblEmpty, 0, 32dip, rowWidth, 40dip)

	clvRequestItems.Add(pnlEmpty, "empty")
	lblStatus.Text = message
End Sub

Private Sub GetRequestRowWidth As Int
	If clvRequestItems.IsInitialized And clvRequestItems.AsView.Width > 0 Then
		Return clvRequestItems.AsView.Width
	End If
	If Activity.Width > 0 Then
		Return Activity.Width
	End If
	Return 320dip
End Sub

Private Sub GetRequestUserId As Int
	If Main.SelectedOrderTakerUserID > 0 Then Return Main.SelectedOrderTakerUserID
	Return Main.LoggedInUserID
End Sub

Private Sub GetRequestVendorId As Int
	If Main.SelectedOrderTakerVendorID > 0 Then Return Main.SelectedOrderTakerVendorID
	Return Main.VENDOR_ID
End Sub

Private Sub GetColumnInt(rs As ResultSet, columnName As String) As Int
	Try
		If HasColumn("items", columnName) Then
			Return rs.GetInt(columnName)
		End If
	Catch
		Log("GetColumnInt error for " & columnName & ": " & LastException.Message)
	End Try
	Return 0
End Sub

Private Sub ParseQty(textValue As String) As Int
	If textValue = Null Then Return 0
	If IsNumber(textValue) = False Then Return 0
	Dim qty As Int = textValue.Trim
	If qty < 0 Then qty = 0
	If qty > MAX_REQUEST_QTY_PER_ITEM Then qty = MAX_REQUEST_QTY_PER_ITEM
	Return qty
End Sub

Private Sub HasColumn(TableName As String, ColumnName As String) As Boolean
	Dim rs As ResultSet
	Try
		rs = Main.SQLProducts.ExecQuery2("PRAGMA table_info(" & TableName & ")", Array As String())
		Do While rs.NextRow
			If rs.GetString("name").ToLowerCase = ColumnName.ToLowerCase Then
				rs.Close
				Return True
			End If
		Loop
		rs.Close
	Catch
		If rs.IsInitialized Then rs.Close
		Log("HasColumn error on " & TableName & "." & ColumnName & ": " & LastException.Message)
	End Try
	Return False
End Sub

Private Sub IsDeviceOnline As Boolean
	Try
		Dim jo As JavaObject
		jo.InitializeContext
		Dim cm As JavaObject = jo.RunMethod("getSystemService", Array("connectivity"))
		If cm.IsInitialized = False Then Return False

		Dim ni As JavaObject = cm.RunMethod("getActiveNetworkInfo", Null)
		If ni.IsInitialized = False Then Return False

		Return ni.RunMethod("isConnected", Null)
	Catch
		Log("IsDeviceOnline error: " & LastException.Message)
		Return False
	End Try
End Sub

Private Sub GetStringValue(source As Map, key As String) As String
	If source.IsInitialized = False Then Return ""
	If source.ContainsKey(key) = False Then Return ""
	If source.Get(key) = Null Then Return ""
	Return source.Get(key)
End Sub

Private Sub EnsureLocalSchema
	If Main.SQLProducts.IsInitialized = False Then Return
	If HasColumn("items", "assigned_stock") = False Then Main.SQLProducts.ExecNonQuery("ALTER TABLE items ADD COLUMN assigned_stock INTEGER DEFAULT 0")
	If HasColumn("items", "used_stock") = False Then Main.SQLProducts.ExecNonQuery("ALTER TABLE items ADD COLUMN used_stock INTEGER DEFAULT 0")
	If HasColumn("items", "remaining_stock") = False Then Main.SQLProducts.ExecNonQuery("ALTER TABLE items ADD COLUMN remaining_stock INTEGER DEFAULT 0")
End Sub
