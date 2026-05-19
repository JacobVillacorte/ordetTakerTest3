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
	Private pnlWholeSupervisor As Panel
	Private pnlDim As Panel
	Private pnlTop As Panel
	Private lblBack As Label
	Private lblTitle As Label
	Private lblSubTitle As Label
	Private lblRefresh As Label
	Private pnlBody As Panel
	Private etSearch As EditText
	Private lblStatus As Label
	Private clvOrderTakers As CustomListView
	Private pnlConfirm As Panel
	Private lblConfirmTitle As Label
	Private lblConfirmName As Label
	Private lblConfirmLogin As Label
	Private lblConfirmVendor As Label
	Private bttnCancel As Button
	Private bttnProceed As Button
	Private btnGoToQueue As Button
	Private orderTakerRows As List
	Private currentLoadJob As HttpJob
	Private selectedUserId As Int = 0
	Private selectedRowData As Map
End Sub

Sub Activity_Create(FirstTime As Boolean)
	Activity.LoadLayout("SupervisorOrderTakerSelection")
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	If pnlConfirm.IsInitialized Then
		If pnlConfirm.NumberOfViews >= 6 Then
			bttnCancel = pnlConfirm.GetView(4)
			bttnProceed = pnlConfirm.GetView(5)
		End If
	End If

	orderTakerRows.Initialize
	selectedUserId = 0
	selectedRowData.Initialize
	HideConfirmPanel
	If pnlDim.IsInitialized Then
		pnlDim.Visible = False
	End If
	If pnlConfirm.IsInitialized Then
		pnlConfirm.Visible = False
	End If
	If lblSubTitle.IsInitialized Then
		lblSubTitle.Text = "Select the order taker you want to view"
	End If
	If lblConfirmTitle.IsInitialized Then
		lblConfirmTitle.Text = "View this order taker?"
	End If
	LoadOrderTakers
End Sub

Sub Activity_Resume
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	If orderTakerRows.IsInitialized = False Or orderTakerRows.Size = 0 Then
		LoadOrderTakers
	Else
		ApplySearchFilter
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

Private Sub LoadOrderTakers
	lblStatus.Text = "Loading order takers..."
	clvOrderTakers.Clear

	Dim job As HttpJob
	job.Initialize("load_order_takers", Me)
	currentLoadJob = job
	job.Download(Main.API_URL & "API/get_order_takers.php?convention_id=" & Main.LoggedInConventionID & "&limit=200")

	Wait For (job) JobDone(job As HttpJob)
	If job.Success = False Then
		lblStatus.Text = "Unable to load order takers."
		ToastMessageShow("Unable to load order takers.", True)
		job.Release
		currentLoadJob = Null
		Return
	End If

	Try
		Dim parser As JSONParser
		parser.Initialize(job.GetString)
		Dim root As Map = parser.NextObject
		Dim status As String = root.Get("status")

		If status <> "success" Then
			Dim message As String = "Failed to load order takers."
			If root.ContainsKey("message") And root.Get("message") <> Null Then message = root.Get("message")
			lblStatus.Text = message
			ToastMessageShow(message, True)
			job.Release
			currentLoadJob = Null
			Return
		End If

		orderTakerRows.Initialize
		Dim data As List = root.Get("data")
		For Each row As Map In data
			orderTakerRows.Add(row)
		Next

		lblStatus.Text = orderTakerRows.Size & " order taker(s) loaded"
		ApplySearchFilter
	Catch
		lblStatus.Text = "Invalid response from server."
		ToastMessageShow("Invalid response from server.", True)
	End Try

	job.Release
	currentLoadJob = Null
End Sub

Private Sub ApplySearchFilter
	clvOrderTakers.Clear
	selectedUserId = 0
	selectedRowData.Initialize

	If orderTakerRows.IsInitialized = False Then Return

	Dim searchText As String = etSearch.Text.Trim.ToLowerCase
	Dim shownCount As Int = 0

	For Each row As Map In orderTakerRows
		Dim loginName As String = GetStringValue(row, "login_name")
		Dim fullName As String = GetStringValue(row, "full_name")
		Dim vendorSummary As String = GetVendorSummary(row)

		If searchText <> "" Then
			Dim haystack As String = (loginName & " " & fullName & " " & vendorSummary).ToLowerCase
			If haystack.Contains(searchText) = False Then
				Continue
			End If
		End If

		Dim userId As Int = GetIntValue(row, "user_id")
		Dim itemPanel As Panel = BuildRowPanel(row)
		clvOrderTakers.Add(itemPanel, userId)
		shownCount = shownCount + 1
	Next

	If shownCount = 0 Then
		lblStatus.Text = "No order takers found."
	Else
		lblStatus.Text = shownCount & " order taker(s) shown"
	End If
End Sub

Private Sub BuildRowPanel(row As Map) As Panel
	Dim pnl As Panel
	pnl.Initialize("")
	pnl.SetLayout(0, 0, clvOrderTakers.AsView.Width, 84dip)

	Dim userId As Int = GetIntValue(row, "user_id")
	Dim loginName As String = GetStringValue(row, "login_name")
	Dim fullName As String = GetStringValue(row, "full_name")
	Dim vendorSummary As String = GetVendorSummary(row)
	Dim isSelected As Boolean = (selectedUserId = userId)

	If isSelected Then
		pnl.Color = Colors.RGB(230, 245, 255)
	Else
		pnl.Color = Colors.White
	End If

	Dim lblName As Label
	lblName.Initialize("")
	lblName.Text = fullName
	lblName.TextSize = 17
	lblName.TextColor = Colors.Black
	lblName.Typeface = Typeface.DEFAULT_BOLD
	pnl.AddView(lblName, 14dip, 10dip, 74%x, 24dip)

	Dim lblLogin As Label
	lblLogin.Initialize("")
	lblLogin.Text = "@" & loginName & "  |  ID: " & userId
	lblLogin.TextSize = 12
	lblLogin.TextColor = Colors.Gray
	pnl.AddView(lblLogin, 14dip, 36dip, 76%x, 18dip)

	Dim lblVendor As Label
	lblVendor.Initialize("")
	lblVendor.Text = vendorSummary
	lblVendor.TextSize = 12
	lblVendor.TextColor = Colors.RGB(75, 95, 125)
	pnl.AddView(lblVendor, 14dip, 54dip, 76%x, 18dip)

	Return pnl
End Sub

Private Sub GetVendorSummary(row As Map) As String
	Dim vendorCount As Int = GetIntValue(row, "vendor_count")
	If vendorCount <= 0 Then
		Return "No vendor assignment"
	End If

	Dim vendorId As Int = GetIntValue(row, "vendor_id")
	Dim vendors As List = Null
	If row.ContainsKey("assigned_vendors") And row.Get("assigned_vendors") <> Null Then
		vendors = row.Get("assigned_vendors")
	End If

	If vendorCount = 1 And vendors.IsInitialized And vendors.Size > 0 Then
		Dim firstVendor As Map = vendors.Get(0)
		Dim vendorName As String = GetStringValue(firstVendor, "vendor_name")
		If vendorName <> "" Then
			Return "Vendor: " & vendorName & " (" & vendorId & ")"
		End If
	End If

	Return "Vendors assigned: " & vendorCount
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

Private Sub FindRowByUserId(userId As Int) As Map
	For Each row As Map In orderTakerRows
		If GetIntValue(row, "user_id") = userId Then
			Return row
		End If
	Next
	Dim emptyMap As Map
	emptyMap.Initialize
	Return emptyMap
End Sub

Private Sub etSearch_TextChanged (Old As String, New As String)
	ApplySearchFilter
End Sub

Private Sub lblRefresh_Click
	LoadOrderTakers
End Sub

Private Sub btnGoToQueue_Click
	StartActivity(SupervisorStockRequestQueue)
	Activity.Finish
End Sub

Private Sub lblBack_Click
	CallSub(Main, "ResetSessionForLogout")
	StartActivity(Main)
	Activity.Finish
End Sub

Private Sub pnlDim_Click
	HideConfirmPanel
End Sub


Private Sub bttnCancel_Click
	HideConfirmPanel
	selectedUserId = 0
	selectedRowData.Initialize
	ApplySearchFilter
End Sub

Private Sub bttnProceed_Click
	If selectedUserId <= 0 Then
		ToastMessageShow("Choose an order taker first.", False)
		Return
	End If

	Dim selectedRow As Map = selectedRowData
	If selectedRow.IsInitialized = False Or selectedRow.Size = 0 Then
		ToastMessageShow("Selected order taker not found.", True)
		Return
	End If

	Main.SelectedOrderTakerUserID = GetIntValue(selectedRow, "user_id")
	Main.SelectedOrderTakerLoginName = GetStringValue(selectedRow, "login_name")
	Main.SelectedOrderTakerFullName = GetStringValue(selectedRow, "full_name")
	Main.SelectedOrderTakerGroupID = GetIntValue(selectedRow, "group_id")
	Main.SelectedOrderTakerRequiresVendorSelection = False
	Main.SelectedOrderTakerAssignedVendors.Initialize

	If selectedRow.ContainsKey("assigned_vendors") And selectedRow.Get("assigned_vendors") <> Null Then
		Main.SelectedOrderTakerAssignedVendors = selectedRow.Get("assigned_vendors")
	End If

	Main.SelectedOrderTakerVendorID = GetIntValue(selectedRow, "vendor_id")
	If Main.SelectedOrderTakerVendorID <= 0 And Main.SelectedOrderTakerAssignedVendors.IsInitialized And Main.SelectedOrderTakerAssignedVendors.Size > 0 Then
		Dim firstVendor As Map = Main.SelectedOrderTakerAssignedVendors.Get(0)
		Main.SelectedOrderTakerVendorID = GetIntValue(firstVendor, "vendor_id")
	End If

	If Main.SelectedOrderTakerAssignedVendors.IsInitialized Then
		Main.SelectedOrderTakerRequiresVendorSelection = (Main.SelectedOrderTakerAssignedVendors.Size > 1)
	End If

	Main.LoggedInRequiresVendorSelection = False
	Main.COPY_ORDER_SOURCE_ID = 0

	ToastMessageShow("Viewing " & Main.SelectedOrderTakerFullName, False)
	StartActivity(SupervisorSyncedOrders)
	Activity.Finish
End Sub

Private Sub clvOrderTakers_ItemClick (Index As Int, Value As Object)
	selectedUserId = Value
	selectedRowData = FindRowByUserId(selectedUserId)
	If selectedRowData.IsInitialized = False Or selectedRowData.Size = 0 Then
		ToastMessageShow("Selected order taker not found.", True)
		Return
	End If

	ShowConfirmPanel(selectedRowData)
End Sub

Private Sub ShowConfirmPanel(row As Map)
	If pnlDim.IsInitialized Then pnlDim.Visible = True
	If pnlConfirm.IsInitialized Then pnlConfirm.Visible = True
	If pnlDim.IsInitialized Then pnlDim.BringToFront
	If pnlConfirm.IsInitialized Then pnlConfirm.BringToFront

	Dim fullName As String = GetStringValue(row, "full_name")
	Dim loginName As String = GetStringValue(row, "login_name")
	lblConfirmName.Text = fullName
	lblConfirmLogin.Text = "@" & loginName
	lblConfirmVendor.Text = GetVendorSummary(row)
End Sub

Private Sub HideConfirmPanel
	If pnlConfirm.IsInitialized Then pnlConfirm.Visible = False
	If pnlDim.IsInitialized Then pnlDim.Visible = False
End Sub
