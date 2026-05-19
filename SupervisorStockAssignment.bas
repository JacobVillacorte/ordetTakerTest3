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
	Private pnlSupervisorstockassignment As Panel
	Private lblBack As Label
	Private lblTitle As Label
	Private lblSubTitle As Label
	Private lblStatus As Label
	Private lvItems As ListView
	Private lblSelectedItem As Label
	Private lblCurrentStock As Label
	Private etAssignedQty As EditText
	Private btnSave As Button
	Private btnClear As Button
	Private currentLoadJob As HttpJob
	Private itemRows As List
	Private stockRowsByItemId As Map
	Private selectedItemRow As Map
End Sub

Sub Activity_Create(FirstTime As Boolean)
	Activity.LoadLayout("SupervisorStockAssignment")
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If

	itemRows.Initialize
	stockRowsByItemId.Initialize
	selectedItemRow.Initialize

	If lblSubTitle.IsInitialized Then
		lblSubTitle.Text = Main.SelectedOrderTakerFullName & " (@" & Main.SelectedOrderTakerLoginName & ")"
	End If

	LoadStockData
End Sub

Sub Activity_Resume
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	If itemRows.IsInitialized = False Or itemRows.Size = 0 Then
		LoadStockData
	End If
End Sub

Sub Activity_Pause(UserClosed As Boolean)
	If currentLoadJob <> Null Then
		Try
			If currentLoadJob.IsInitialized Then
				currentLoadJob.Release
			End If
		Catch
			Log(LastException.Message)
		End Try
		currentLoadJob = Null
	End If
End Sub

Private Sub LoadStockData
	If Main.SelectedOrderTakerUserID <= 0 Then
		lblStatus.Text = "No selected order taker."
		ToastMessageShow("Select an order taker first.", True)
		Return
	End If

	Dim vendorId As Int = ResolveVendorIdForStock
	If vendorId <= 0 Then
		lblStatus.Text = "No vendor assigned to this order taker."
		ToastMessageShow("No vendor assigned to this order taker.", True)
		Return
	End If

	lblStatus.Text = "Loading items..."
	lvItems.Clear
	itemRows.Initialize
	stockRowsByItemId.Initialize
	selectedItemRow.Initialize
	UpdateSelectedItemDisplay

	Dim itemJob As HttpJob
	itemJob.Initialize("load_stock_items", Me)
	currentLoadJob = itemJob
	Dim itemUrl As String = Main.API_URL & "API/get_items.php?vendor_id=" & vendorId & "&convention_id=" & Main.LoggedInConventionID & "&limit=500"
	itemJob.Download(itemUrl)

	Wait For (itemJob) JobDone(jobItems As HttpJob)
	If jobItems.Success = False Then
		lblStatus.Text = "Unable to load items."
		ToastMessageShow("Unable to load items.", True)
		jobItems.Release
		currentLoadJob = Null
		Return
	End If

	Try
		Dim parser As JSONParser
		parser.Initialize(jobItems.GetString)
		Dim root As Map = parser.NextObject
		If root.Get("status") <> "success" Then
			lblStatus.Text = GetStringValue(root, "message")
			ToastMessageShow(lblStatus.Text, True)
			jobItems.Release
			currentLoadJob = Null
			Return
		End If

		Dim data As List = root.Get("data")
		For Each row As Map In data
			itemRows.Add(row)
		Next
	Catch
		lblStatus.Text = "Invalid items response."
		ToastMessageShow("Invalid items response.", True)
		jobItems.Release
		currentLoadJob = Null
		Return
	End Try

	jobItems.Release
	currentLoadJob = Null
	LoadAssignedStock
End Sub

Private Sub LoadAssignedStock
	lblStatus.Text = "Loading assigned stock..."

	Dim stockJob As HttpJob
	stockJob.Initialize("load_assigned_stock", Me)
	currentLoadJob = stockJob
	Dim stockUrl As String = Main.API_URL & "API/get_order_taker_stock.php?convention_id=" & Main.LoggedInConventionID & _
		"&user_id=" & Main.SelectedOrderTakerUserID & "&vendor_id=" & ResolveVendorIdForStock & "&limit=500"
	stockJob.Download(stockUrl)

	Wait For (stockJob) JobDone(jobStock As HttpJob)
	If jobStock.Success = False Then
		lblStatus.Text = "Unable to load stock."
		ToastMessageShow("Unable to load stock.", True)
		jobStock.Release
		currentLoadJob = Null
		Return
	End If

	Try
		Dim parser As JSONParser
		parser.Initialize(jobStock.GetString)
		Dim root As Map = parser.NextObject
		If root.Get("status") = "success" Then
			Dim data As List = root.Get("data")
			For Each row As Map In data
				Dim itemId As Int = GetIntValue(row, "item_id")
				stockRowsByItemId.Put(itemId, row)
			Next
		End If
	Catch
		Log("LoadAssignedStock parse error: " & LastException.Message)
	End Try

	jobStock.Release
	currentLoadJob = Null
	RenderItemList
End Sub

Private Sub RenderItemList
	lvItems.Clear

	For Each row As Map In itemRows
		Dim itemId As Int = GetIntValue(row, "item_id")
		Dim itemName As String = GetStringValue(row, "item_name")
		If itemName = "" Then itemName = GetStringValue(row, "item_description")
		Dim itemCode As String = GetStringValue(row, "item_code")
		Dim unitPrice As Double = GetDoubleValue(row, "unit_price")

		Dim assignedStock As Int = 0
		Dim usedStock As Int = 0
		Dim remainingStock As Int = 0

		If stockRowsByItemId.ContainsKey(itemId) Then
			Dim stockRow As Map = stockRowsByItemId.Get(itemId)
			assignedStock = GetIntValue(stockRow, "assigned_stock")
			usedStock = GetIntValue(stockRow, "used_stock")
			remainingStock = GetIntValue(stockRow, "remaining_stock")
		End If

		Dim summary As String = itemName & " | " & itemCode & " | ₱" & NumberFormat2(unitPrice, 1, 2, 2, False)
		summary = summary & CRLF & "Assigned " & assignedStock & " | Used " & usedStock & " | Left " & remainingStock

		lvItems.AddSingleLine2(summary, row)
	Next

	If itemRows.Size = 0 Then
		lblStatus.Text = "No items found for this vendor."
	Else
		lblStatus.Text = itemRows.Size & " item(s) ready"
	End If
End Sub

Private Sub lvItems_ItemClick (Position As Int, Value As Object)
	If (Value Is Map) = False Then Return
	selectedItemRow = Value
	UpdateSelectedItemDisplay
End Sub

Private Sub UpdateSelectedItemDisplay
	If selectedItemRow.IsInitialized = False Or selectedItemRow.Size = 0 Then
		lblSelectedItem.Text = "Select an item"
		lblCurrentStock.Text = "Assigned / Used / Left"
		etAssignedQty.Text = ""
		Return
	End If

	Dim itemId As Int = GetIntValue(selectedItemRow, "item_id")
	Dim itemName As String = GetStringValue(selectedItemRow, "item_name")
	If itemName = "" Then itemName = GetStringValue(selectedItemRow, "item_description")
	Dim itemCode As String = GetStringValue(selectedItemRow, "item_code")
	Dim unitPrice As Double = GetDoubleValue(selectedItemRow, "unit_price")

	lblSelectedItem.Text = itemName & " | " & itemCode & " | ₱" & NumberFormat2(unitPrice, 1, 2, 2, False)

	Dim assignedStock As Int = 0
	Dim usedStock As Int = 0
	Dim remainingStock As Int = 0
	If stockRowsByItemId.ContainsKey(itemId) Then
		Dim stockRow As Map = stockRowsByItemId.Get(itemId)
		assignedStock = GetIntValue(stockRow, "assigned_stock")
		usedStock = GetIntValue(stockRow, "used_stock")
		remainingStock = GetIntValue(stockRow, "remaining_stock")
	End If

	lblCurrentStock.Text = "Assigned " & assignedStock & " | Used " & usedStock & " | Left " & remainingStock
	etAssignedQty.Text = "" & assignedStock
End Sub

Private Sub btnSave_Click
	If selectedItemRow.IsInitialized = False Or selectedItemRow.Size = 0 Then
		ToastMessageShow("Select an item first.", True)
		Return
	End If

	If IsNumber(etAssignedQty.Text) = False Then
		ToastMessageShow("Enter a valid stock quantity.", True)
		Return
	End If

	Dim assignedQty As Int = etAssignedQty.Text.Trim
	If assignedQty < 0 Then
		ToastMessageShow("Stock cannot be negative.", True)
		Return
	End If

	SaveStockAssignment(selectedItemRow, assignedQty)
End Sub

Private Sub SaveStockAssignment(itemRow As Map, assignedQty As Int)
	Dim payload As Map
	payload.Initialize
	payload.Put("convention_id", Main.LoggedInConventionID)
	payload.Put("user_id", Main.SelectedOrderTakerUserID)
	payload.Put("item_id", GetIntValue(itemRow, "item_id"))
	payload.Put("assigned_qty", assignedQty)
	payload.Put("device_id", Main.SelectedOrderTakerLoginName)
	payload.Put("status", "active")

	Dim jg As JSONGenerator
	jg.Initialize(payload)

	Dim job As HttpJob
	job.Initialize("save_order_taker_stock", Me)
	currentLoadJob = job
	job.PostString(Main.API_URL & "API/save_order_taker_stock.php", jg.ToString)
	job.GetRequest.SetContentType("application/json")

	Wait For (job) JobDone(jobSave As HttpJob)
	If jobSave.Success = False Then
		ToastMessageShow("Unable to save stock.", True)
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

		ToastMessageShow("Stock saved.", False)
		jobSave.Release
		currentLoadJob = Null
		LoadStockData
	Catch
		ToastMessageShow("Invalid save response.", True)
	End Try
End Sub

Private Sub btnClear_Click
	selectedItemRow.Initialize
	UpdateSelectedItemDisplay
End Sub

Private Sub btnReload_Click
	LoadStockData
End Sub

Private Sub lblBack_Click
	StartActivity(SupervisorSyncedOrders)
	Activity.Finish
End Sub

Private Sub ResolveVendorIdForStock As Int
	If Main.SelectedOrderTakerVendorID > 0 Then Return Main.SelectedOrderTakerVendorID
	If Main.SelectedOrderTakerAssignedVendors.IsInitialized And Main.SelectedOrderTakerAssignedVendors.Size > 0 Then
		Dim firstVendor As Map = Main.SelectedOrderTakerAssignedVendors.Get(0)
		Return GetIntValue(firstVendor, "vendor_id")
	End If
	Return 0
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