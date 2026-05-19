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
	' Cart - holds cart item maps with product info and quantity
	Private CartItems As List

	' Multi-selection tracking
	Private SelectedItems As List           ' Stores selected items for deletion
	Private SelectedIndices As List         ' Optional, can track indexes if needed for highlighting
	Private SelectionMode As Boolean = False

	' Stores info about the item the user is currently selecting a quantity for
	Private SelectedItemID As Int
	Private SelectedItemName As String
	Private SelectedItemPrice As Double
	Private SelectedItemCode As String
	Private LastClickedProductID As Int = 0  ' Track the most recently clicked product
	
	' Main cart screen
	Private pnladdOrderActivityTop As Panel
	Private pnladdOrderActivityWhole As Panel
	Private pnlDim As Panel
	Private clvCartSummary As CustomListView
	Private lblTotalItems As Label
	Private lblTotalAmount As Label
	Private bttnPurchaseNow As Button
	Private lblExitOrderActivity As Label
	Private bttnAddOrderActivity As Button
	
	' Product selection popup
	Private pnlSelectItems As Panel
	Private clvProducts As CustomListView
	Private etSearchProducts As EditText
	Private lblExitSelectItems As Label

	' Quantity selector popup
	Private pnlQuantity As Panel
	Private lblQuantityTitle As Label
	Private lblSelectedItem As Label
	Private etQuantityValue As EditText
	Private bttnMinus As Button
	Private bttnAdd As Button
	Private bttnAddToCartQty As Button
	Private bttnCancelQty As Button
	
	' Purchase status popup
	Private pnlPurchaseStatus As Panel
	Private lblPurchaseStatusTitle As Label
	Private lblPurchaseStatusMessage As Label
	Private rbPaidReceived As RadioButton
	Private rbPaidBooked As RadioButton
	Private rbNotPaidBooked As RadioButton
	Private bttnConfirmPurchaseStatus As Button
	Private bttnCancelPurchaseStatus As Button
	
	' Fulfillment toggle state
	Private IsPaidSelected As Boolean = True
	Private IsReceivedSelected As Boolean = True
	Private IsBookedSelected As Boolean = False
	Private IgnoreRadioChanges As Boolean = False
	
	' Delete selection buttons / popup
	Private btnDeleteSelected As Button
	Private btnNoDelete As Button
	Private btnYesDelete As Button
	Private PnlConfirmDelete As Panel
End Sub

Sub Activity_Create(FirstTime As Boolean)
	Activity.LoadLayout("addOrderActivity")
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If

	If Main.VENDOR_ID <= 0 Or Main.LoggedInUserID <= 0 Then
		ToastMessageShow("Session is invalid. Please login again.", True)
		Activity.Finish
		Return
	End If

	CartItems.Initialize
	SelectedItems.Initialize
	SelectedIndices.Initialize

	ApplyPendingCopyOrder

	pnlPurchaseStatus.Visible = False
	InitFulfillmentToggles
	btnDeleteSelected.Enabled = True
	btnDeleteSelected.Color = Colors.ARGB(80, 200, 200, 200)
	PnlConfirmDelete.Visible = False

	LoadProductsIntoList
End Sub

Sub Activity_Resume
	If Main.LoggedInUserID <= 0 Then
		Activity.Finish
		Return
	End If
	ApplyPendingCopyOrder
End Sub

Private Sub ApplyPendingCopyOrder
	If Main.COPY_ORDER_SOURCE_ID <= 0 Then
		If CartItems.Size > 0 Then
			bttnPurchaseNow.Enabled = True
			bttnPurchaseNow.Color = Colors.Blue
		Else
			bttnPurchaseNow.Enabled = False
			bttnPurchaseNow.Color = Colors.ARGB(80, 200, 200, 200)
		End If
		Return
	End If

	If CartItems.IsInitialized Then CartItems.Clear
	LoadCopiedOrderIntoCart(Main.COPY_ORDER_SOURCE_ID)
	Main.COPY_ORDER_SOURCE_ID = 0

	If CartItems.Size > 0 Then
		bttnPurchaseNow.Enabled = True
		bttnPurchaseNow.Color = Colors.Blue
	Else
		bttnPurchaseNow.Enabled = False
		bttnPurchaseNow.Color = Colors.ARGB(80, 200, 200, 200)
	End If
End Sub

Private Sub LoadCopiedOrderIntoCart(sourceOrderID As Int)
	Try
		Dim rsOrder As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT customer_id, customer_code, customer_name, customer_owner, customer_address FROM orders WHERE order_id = ?", _
			Array As String(sourceOrderID))

		If rsOrder.NextRow Then
			Main.SELECTED_CUSTOMER_ID = rsOrder.GetInt("customer_id")
			Main.SELECTED_CUSTOMER_CODE = rsOrder.GetString("customer_code")
			Main.SELECTED_CUSTOMER_NAME = rsOrder.GetString("customer_name")
			Main.SELECTED_CUSTOMER_OWNER = rsOrder.GetString("customer_owner")
			Main.SELECTED_CUSTOMER_ADDRESS = rsOrder.GetString("customer_address")
		End If
		rsOrder.Close

		Dim rsItems As ResultSet = Main.SQLProducts.ExecQuery2( _
			"SELECT oi.product_id, oi.quantity, oi.price, i.item_name, i.item_code " & _
			"FROM order_items oi " & _
			"LEFT JOIN items i ON oi.product_id = i.item_id " & _
			"WHERE oi.order_id = ? ORDER BY oi.order_item_id", _
			Array As String(sourceOrderID))

		Do While rsItems.NextRow
			Dim cartItem As Map
			cartItem.Initialize
			cartItem.Put("product_id", rsItems.GetInt("product_id"))
			Dim itemName As String = rsItems.GetString("item_name")
			If itemName = Null Or itemName = "" Then itemName = "Item #" & rsItems.GetInt("product_id")
			cartItem.Put("item_name", itemName)
			cartItem.Put("unit_price", rsItems.GetDouble("price"))
			cartItem.Put("quantity", rsItems.GetInt("quantity"))
			Dim itemCode As String = rsItems.GetString("item_code")
			If itemCode = Null Then itemCode = ""
			cartItem.Put("item_code", itemCode)
			CartItems.Add(cartItem)
		Loop
		rsItems.Close

		RefreshCartDisplay
	Catch
		Log("LoadCopiedOrderIntoCart error: " & LastException.Message)
	End Try
End Sub

Sub Activity_Pause(UserClosed As Boolean)
End Sub

' ======================
' TRANSACTION NUMBER
' ======================

Sub GenerateTransactionNumber As String
	Try
		Dim safeDeviceID As String = Main.DEVICE_ID
		If safeDeviceID = Null Or safeDeviceID = "" Then safeDeviceID = "UNKNOWNDEVICE"

		Dim cursor As Cursor = Main.SQLProducts.ExecQuery2( _
            "SELECT transaction_number FROM orders WHERE device_id = ? ORDER BY order_id DESC LIMIT 1", _
            Array As String(safeDeviceID))

		Dim nextSequence As Int = 1

		If cursor.RowCount > 0 Then
			cursor.Position = 0
			Dim lastTransaction As String = cursor.GetString("transaction_number")
			If lastTransaction <> Null And lastTransaction.Contains("-") Then
				Dim parts() As String = Regex.Split("-", lastTransaction)
				If parts.Length >= 2 Then
					nextSequence = parts(parts.Length - 1) + 1
				End If
			End If
		End If
		cursor.Close

		Return safeDeviceID & "-" & NumberFormat(nextSequence, 3, 0)

	Catch
		Log("GenerateTransactionNumber error: " & LastException.Message)
		Return Main.DEVICE_ID & "-ERR"
	End Try
End Sub

' ======================
' MAIN CART SCREEN
' ======================

Private Sub bttnAddOrderActivity_Click
	pnlDim.Visible = True
	pnlSelectItems.Visible = True
	pnlDim.BringToFront
	pnlSelectItems.BringToFront
	Sleep(0)
	LoadProductsIntoList
End Sub

Private Sub lblExitSelectItems_Click
	pnlDim.Visible = False
	pnlSelectItems.Visible = False
End Sub

Private Sub lblExitOrderActivity_Click
	Activity.Finish
End Sub

Private Sub bttnPurchaseNow_Click
	If CartItems.Size = 0 Then
		ToastMessageShow("Add items first", True)
		Return
	End If

	' Make sure dim panel is visible and on top
	pnlDim.Visible = True
	pnlDim.BringToFront

	' Show the purchase status popup
	pnlPurchaseStatus.Visible = True
	pnlPurchaseStatus.BringToFront

	' Reset toggle states to default (Paid + Received)
	IsPaidSelected = True
	IsReceivedSelected = True
	IsBookedSelected = False
	UpdateToggleVisuals
	LayoutPurchaseStatusOptions
End Sub

Private Sub HidePurchaseStatusPopup
	pnlPurchaseStatus.Visible = False
	pnlDim.Visible = False
End Sub

' Tighten spacing of the status options inside the popup.
Private Sub LayoutPurchaseStatusOptions
	If rbPaidReceived.IsInitialized = False Or rbPaidBooked.IsInitialized = False Or rbNotPaidBooked.IsInitialized = False Then Return
	If lblPurchaseStatusMessage.IsInitialized = False Or bttnConfirmPurchaseStatus.IsInitialized = False Then Return
	
	Dim startY As Int = lblPurchaseStatusMessage.Top + lblPurchaseStatusMessage.Height + 12dip
	Dim maxBottom As Int = bttnConfirmPurchaseStatus.Top - 10dip
	Dim available As Int = maxBottom - startY
	If available <= 0 Then Return
	
	Dim optionH As Int = 38dip
	Dim gap As Int = 8dip
	Dim needed As Int = (3 * optionH) + (2 * gap)
	If needed > available Then
		gap = 4dip
		optionH = Max(30dip, (available - 2 * gap) / 3)
	End If
	
	rbPaidReceived.Height = optionH
	rbPaidBooked.Height = optionH
	rbNotPaidBooked.Height = optionH
	
	rbPaidReceived.Top = startY
	rbPaidBooked.Top = rbPaidReceived.Top + optionH + gap
	rbNotPaidBooked.Top = rbPaidBooked.Top + optionH + gap
End Sub

Private Sub GetSelectedCount As Int
	Dim count As Int = 0
	If IsPaidSelected Then count = count + 1
	If IsReceivedSelected Then count = count + 1
	If IsBookedSelected Then count = count + 1
	Return count
End Sub

' Received only: goods received, not paid, not booked (stored as NotPaid-Received).
Private Sub IsReceivedOnlyFulfillment As Boolean
	Return IsReceivedSelected And Not(IsPaidSelected) And Not(IsBookedSelected)
End Sub

Private Sub IsReceivedBookedPaired As Boolean
	Return IsReceivedSelected And IsBookedSelected
End Sub

Private Sub IsValidFulfillmentSelection As Boolean
	If IsReceivedBookedPaired Then Return False
	If IsReceivedOnlyFulfillment Then Return True
	If GetSelectedCount = 2 Then Return True
	Return False
End Sub

Private Sub GetSelectedFulfillmentStatus As String
	Dim parts As List
	parts.Initialize
	
	If IsPaidSelected Then
		parts.Add("Paid")
	Else
		parts.Add("NotPaid")
	End If
	
	If IsReceivedSelected Then parts.Add("Received")
	If IsBookedSelected Then parts.Add("Booked")
	
	Dim result As String = ""
	For i = 0 To parts.Size - 1
		If i > 0 Then result = result & "-"
		result = result & parts.Get(i)
	Next
	Return result
End Sub

Private Sub bttnConfirmPurchaseStatus_Click
	If IsReceivedBookedPaired Then
		ToastMessageShow("Received and Booked cannot be used together.", True)
		Return
	End If
	If Not(IsValidFulfillmentSelection) Then
		ToastMessageShow("Pick two options, or only Received (not paid, not booked).", True)
		Return
	End If

	Dim fulfillmentStatus As String = GetSelectedFulfillmentStatus
	SaveOrderToLocalDatabase(fulfillmentStatus)
	HidePurchaseStatusPopup
	ClearCartAndResetUI
	ToastMessageShow("Order added successfully!", False)
	Activity.Finish
End Sub

Private Sub bttnCancelPurchaseStatus_Click
	HidePurchaseStatusPopup
End Sub

Private Sub InitFulfillmentToggles
	IsPaidSelected = True
	IsReceivedSelected = True
	IsBookedSelected = False
	UpdateToggleVisuals
End Sub

Private Sub rbPaidReceived_CheckedChange(Checked As Boolean)
	If IgnoreRadioChanges Then Return
	If Not(Checked) Then Return
	If Not(IsPaidSelected) And GetSelectedCount >= 2 Then
		ToastMessageShow("Deselect one first", False)
		IgnoreRadioChanges = True
		rbPaidReceived.Checked = False
		IgnoreRadioChanges = False
		Return
	End If
	IsPaidSelected = Not(IsPaidSelected)
	UpdateToggleVisuals
End Sub

Private Sub rbPaidBooked_CheckedChange(Checked As Boolean)
	If IgnoreRadioChanges Then Return
	If Not(Checked) Then Return
	If Not(IsReceivedSelected) And IsBookedSelected Then
		ToastMessageShow("Received and Booked cannot be used together.", False)
		IgnoreRadioChanges = True
		rbPaidBooked.Checked = False
		IgnoreRadioChanges = False
		Return
	End If
	If Not(IsReceivedSelected) And GetSelectedCount >= 2 Then
		ToastMessageShow("Deselect one first", False)
		IgnoreRadioChanges = True
		rbPaidBooked.Checked = False
		IgnoreRadioChanges = False
		Return
	End If
	IsReceivedSelected = Not(IsReceivedSelected)
	UpdateToggleVisuals
End Sub

Private Sub rbNotPaidBooked_CheckedChange(Checked As Boolean)
	If IgnoreRadioChanges Then Return
	If Not(Checked) Then Return
	If Not(IsBookedSelected) And IsReceivedSelected Then
		ToastMessageShow("Received and Booked cannot be used together.", False)
		IgnoreRadioChanges = True
		rbNotPaidBooked.Checked = False
		IgnoreRadioChanges = False
		Return
	End If
	If Not(IsBookedSelected) And GetSelectedCount >= 2 Then
		ToastMessageShow("Deselect one first", False)
		IgnoreRadioChanges = True
		rbNotPaidBooked.Checked = False
		IgnoreRadioChanges = False
		Return
	End If
	IsBookedSelected = Not(IsBookedSelected)
	UpdateToggleVisuals
End Sub

Private Sub UpdateToggleVisuals
	IgnoreRadioChanges = True
	
	rbPaidReceived.Checked = False
	rbPaidBooked.Checked = False
	rbNotPaidBooked.Checked = False
	
	If IsPaidSelected Then
		rbPaidReceived.Text = "  ✔ Paid"
		rbPaidReceived.TextColor = Colors.RGB(0, 128, 0)
	Else
		rbPaidReceived.Text = "     Paid"
		rbPaidReceived.TextColor = Colors.DarkGray
	End If
	
	If IsReceivedSelected Then
		rbPaidBooked.Text = "  ✔ Received"
		rbPaidBooked.TextColor = Colors.RGB(0, 128, 0)
	Else
		rbPaidBooked.Text = "     Received"
		rbPaidBooked.TextColor = Colors.DarkGray
	End If
	
	If IsBookedSelected Then
		rbNotPaidBooked.Text = "  ✔ Booked"
		rbNotPaidBooked.TextColor = Colors.RGB(0, 128, 0)
	Else
		rbNotPaidBooked.Text = "     Booked"
		rbNotPaidBooked.TextColor = Colors.DarkGray
	End If
	
	IgnoreRadioChanges = False
End Sub

Private Sub ClearCartAndResetUI
	CartItems.Clear
	RefreshCartDisplay

	bttnPurchaseNow.Color = Colors.ARGB(80, 200, 200, 200)
	bttnPurchaseNow.Enabled = False

	IsPaidSelected = True
	IsReceivedSelected = True
	IsBookedSelected = False
	UpdateToggleVisuals
	ExitSelectionMode
End Sub

Private Sub pnlDim_Click
End Sub

' ======================
' PRODUCT SELECTION POPUP
' ======================

Private Sub etSearchProducts_TextChanged(Old As String, New As String)
	LoadProductsIntoList
End Sub

Private Sub LoadProductsIntoList
	clvProducts.Clear

	If Main.VENDOR_ID <= 0 Then
		ToastMessageShow("No vendor assigned. Please login again.", True)
		Return
	End If

	Dim searchText As String = etSearchProducts.Text.Trim.ToLowerCase
	Dim rs As ResultSet
	Dim vendorIDText As String = Main.VENDOR_ID

	If searchText = "" Then
		rs = Main.SQLProducts.ExecQuery2( _
            "SELECT * FROM items WHERE is_active = 1 AND vendor_id = ? ORDER BY item_name", _
            Array As String(vendorIDText))
	Else
		Dim likeValue As String = "%" & searchText & "%"
		rs = Main.SQLProducts.ExecQuery2( _
            "SELECT * FROM items WHERE is_active = 1 AND vendor_id = ? AND (LOWER(item_name) LIKE ? OR LOWER(item_code) LIKE ?) ORDER BY item_name", _
            Array As String(vendorIDText, likeValue, likeValue))
	End If

	If rs.RowCount = 0 Then
		ToastMessageShow("No products found for your vendor.", False)
		rs.Close
		Return
	End If

	Dim listW As Int = clvProducts.AsView.Width
	If listW <= 0 Then listW = 100%x

	If LastClickedProductID > 0 Then
		Dim pnlRecentSelected As Panel
		pnlRecentSelected.Initialize("")
		pnlRecentSelected.SetLayout(0, 0, listW, 35dip)
		pnlRecentSelected.Color = Colors.RGB(200, 220, 255)

		Dim lblRecentLabel As Label
		lblRecentLabel.Initialize("")
		lblRecentLabel.Text = "Recently Selected ✓"
		lblRecentLabel.TextSize = 12
		lblRecentLabel.TextColor = Colors.RGB(0, 100, 200)
		lblRecentLabel.Typeface = Typeface.DEFAULT_BOLD
		lblRecentLabel.Gravity = Gravity.LEFT
		pnlRecentSelected.AddView(lblRecentLabel, 10dip, 8dip, listW - 20dip, 20dip)

		clvProducts.Add(pnlRecentSelected, -1)
	End If

	Do While rs.NextRow
		Dim productID As Int = rs.GetInt("item_id")

		Dim pnl As Panel
		pnl.Initialize("")
		pnl.SetLayout(0, 0, listW, 90dip)

		If productID = LastClickedProductID Then
			pnl.Color = Colors.RGB(255, 255, 200)
		Else
			pnl.Color = Colors.White
		End If

		Dim lblName As Label
		lblName.Initialize("")
		lblName.Text = rs.GetString("item_name")
		lblName.TextSize = 15
		lblName.Typeface = Typeface.DEFAULT_BOLD
		lblName.TextColor = Colors.Black
		lblName.SetLayout(10dip, 6dip, listW - 20dip, 24dip)

		Dim unitPrice As Double = rs.GetDouble("unit_price")
		Dim lblPrice As Label
		lblPrice.Initialize("")
		lblPrice.Text = "₱" & NumberFormat2(unitPrice, 1, 2, 2, False)
		lblPrice.TextSize = 14
		lblPrice.TextColor = Colors.Black
		lblPrice.SetLayout(10dip, 34dip, listW - 20dip, 22dip)

		Dim lblSku As Label
		lblSku.Initialize("")
		lblSku.Text = "SKU: " & rs.GetString("item_code")
		lblSku.TextSize = 11
		lblSku.TextColor = Colors.RGB(150, 150, 150)
		lblSku.SetLayout(10dip, 60dip, listW - 20dip, 18dip)

		pnl.AddView(lblName, lblName.Left, lblName.Top, lblName.Width, lblName.Height)
		pnl.AddView(lblPrice, lblPrice.Left, lblPrice.Top, lblPrice.Width, lblPrice.Height)
		pnl.AddView(lblSku, lblSku.Left, lblSku.Top, lblSku.Width, lblSku.Height)

		clvProducts.Add(pnl, productID)

		Dim pnlSeparator As Panel
		pnlSeparator.Initialize("")
		pnlSeparator.SetLayout(0, 0, listW, 1dip)
		pnlSeparator.Color = Colors.RGB(230, 230, 230)
		clvProducts.Add(pnlSeparator, -1)
	Loop

	rs.Close
End Sub

Private Sub clvProducts_ItemClick(Index As Int, Value As Object)
	Dim itemID As Int = Value

	Dim rs As ResultSet = Main.SQLProducts.ExecQuery2("SELECT * FROM items WHERE item_id=?", Array As String(itemID))

	If rs.NextRow Then
		SelectedItemID = itemID
		LastClickedProductID = itemID  ' Track the last clicked product
		SelectedItemName = rs.GetString("item_name")
		SelectedItemPrice = rs.GetDouble("unit_price")
		SelectedItemCode = rs.GetString("item_code")

		lblSelectedItem.Text = SelectedItemName & Chr(10) & "₱" & NumberFormat2(SelectedItemPrice, 1, 2, 2, False)
		etQuantityValue.Text = "1"

		pnlDim.Visible = True
		pnlDim.BringToFront
		pnlQuantity.Visible = True
		pnlQuantity.BringToFront
	End If
	rs.Close
End Sub

' ======================
' QUANTITY SELECTOR POPUP
' ======================

Private Sub bttnMinus_Click
	Dim currentQty As Int = etQuantityValue.Text
	If currentQty > 1 Then
		etQuantityValue.Text = (currentQty - 1)
	Else
		ToastMessageShow("Minimum quantity is 1", False)
	End If
End Sub

Private Sub bttnAdd_Click
	Dim currentQty As Int = etQuantityValue.Text
	If currentQty < 999 Then
		etQuantityValue.Text = (currentQty + 1)
	Else
		ToastMessageShow("Maximum quantity is 999", False)
	End If
End Sub

Private Sub bttnAddToCartQty_Click
	If IsNumber(etQuantityValue.Text) = False Then
		ToastMessageShow("Please enter a valid number", True)
		etQuantityValue.Text = "1"
		Return
	End If

	Dim quantity As Int = etQuantityValue.Text

	If quantity < 1 Then
		ToastMessageShow("Minimum quantity is 1", True)
		etQuantityValue.Text = "1"
		Return
	End If

	If quantity > 999 Then
		ToastMessageShow("Maximum quantity is 999", True)
		etQuantityValue.Text = "999"
		Return
	End If

	AddCartItemToList(SelectedItemID, SelectedItemName, SelectedItemPrice, quantity, SelectedItemCode)

	RefreshCartDisplay
	bttnPurchaseNow.Enabled = True
	bttnPurchaseNow.Color = Colors.Blue

	ToastMessageShow("Added " & quantity & "x " & SelectedItemName, False)

	pnlQuantity.Visible = False
	pnlDim.Visible = False
	pnlSelectItems.Visible = False
End Sub

Private Sub bttnCancelQty_Click
	pnlQuantity.Visible = False
	pnlDim.Visible = False
End Sub

' ======================
' CART DISPLAY (CustomListView version)
' ======================

Private Sub RefreshCartDisplay
	clvCartSummary.Clear

	Dim totalAmount As Double = 0
	Dim totalQuantity As Int = 0
	Dim pnlW As Int = clvCartSummary.AsView.Width
	If pnlW <= 0 Then pnlW = 100%x

	For Each cartItem As Map In CartItems
		Dim itemName As String = cartItem.Get("item_name")
		Dim unitPrice As Double = cartItem.Get("unit_price")
		Dim quantity As Int = cartItem.Get("quantity")
		Dim lineTotal As Double = unitPrice * quantity
		Dim itemCode As String = ""
		If cartItem.ContainsKey("item_code") Then itemCode = cartItem.Get("item_code")

		Dim pnl As Panel
		pnl.Initialize("")
		pnl.Color = Colors.White
		pnl.SetLayout(0, 0, pnlW, 88dip)

		Dim lblName As Label
		lblName.Initialize("")
		lblName.Text = itemName
		lblName.TextSize = 15
		lblName.TextColor = Colors.Black
		lblName.Typeface = Typeface.DEFAULT_BOLD
		lblName.SetLayout(10dip, 4dip, pnlW * 0.62, 24dip)

		Dim lblPriceBreakdown As Label
		lblPriceBreakdown.Initialize("")
		lblPriceBreakdown.Text = "₱" & NumberFormat2(unitPrice, 1, 2, 2, False) & " × (" & quantity & ") = ₱" & NumberFormat2(lineTotal, 1, 2, 2, False)
		lblPriceBreakdown.TextSize = 13
		lblPriceBreakdown.TextColor = Colors.DarkGray
		lblPriceBreakdown.SetLayout(10dip, 30dip, pnlW - 20dip, 20dip)

		Dim lblSku As Label
		lblSku.Initialize("")
		lblSku.Text = "SKU: " & itemCode
		lblSku.TextSize = 11
		lblSku.TextColor = Colors.RGB(150, 150, 150)
		lblSku.SetLayout(10dip, 52dip, pnlW * 0.6, 18dip)

		Dim lblLineTotal As Label
		lblLineTotal.Initialize("")
		lblLineTotal.Text = "₱" & NumberFormat2(lineTotal, 1, 2, 2, False)
		lblLineTotal.TextSize = 16
		lblLineTotal.TextColor = Colors.RGB(0, 140, 0)
		lblLineTotal.Gravity = Gravity.RIGHT
		lblLineTotal.Typeface = Typeface.DEFAULT_BOLD
		lblLineTotal.SetLayout(pnlW * 0.62, 4dip, pnlW * 0.35, 25dip)

		pnl.AddView(lblName, lblName.Left, lblName.Top, lblName.Width, lblName.Height)
		pnl.AddView(lblLineTotal, lblLineTotal.Left, lblLineTotal.Top, lblLineTotal.Width, lblLineTotal.Height)
		pnl.AddView(lblPriceBreakdown, lblPriceBreakdown.Left, lblPriceBreakdown.Top, lblPriceBreakdown.Width, lblPriceBreakdown.Height)
		pnl.AddView(lblSku, lblSku.Left, lblSku.Top, lblSku.Width, lblSku.Height)

		clvCartSummary.Add(pnl, CartItems.IndexOf(cartItem))

		totalAmount = totalAmount + lineTotal
		totalQuantity = totalQuantity + quantity
	Next

	lblTotalItems.Text = "Items: " & CartItems.Size & " entries (" & totalQuantity & " total)"
	lblTotalAmount.Text = "Total: ₱" & NumberFormat2(totalAmount, 1, 2, 2, False)
End Sub

' ======================
' SAVE ORDER
' ======================

Private Sub SaveOrderToLocalDatabase(FulfillmentStatus As String)
	Try
		If Main.VENDOR_ID <= 0 Or Main.LoggedInUserID <= 0 Then
			ToastMessageShow("Missing user/vendor session. Please login again.", True)
			Return
		End If

		Dim transactionNumber As String = GenerateTransactionNumber
		Dim total As Double = 0
		Dim totalQuantity As Int = 0

		For Each cartItem As Map In CartItems
			Dim unitPrice As Double = cartItem.Get("unit_price")
			Dim quantity As Int = cartItem.Get("quantity")
			total = total + (unitPrice * quantity)
			totalQuantity = totalQuantity + quantity
		Next

		Dim bookingValue As Int = GetBookingFromFulfillmentStatus(FulfillmentStatus)
		Dim prepaidValue As Int = GetPrepaidFromFulfillmentStatus(FulfillmentStatus)

		Main.SQLProducts.ExecNonQuery2( _
			"INSERT INTO orders (vendor_id, user_id, convention_id, transaction_number, device_id, date_created, status, total_amount, item_count, booking, prepaid, sync_status, customer_id, customer_code, customer_name, customer_owner, customer_address) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", _
			Array As Object(Main.VENDOR_ID, Main.LoggedInUserID, Main.LoggedInConventionID, transactionNumber, Main.DEVICE_ID, DateTime.Now, FulfillmentStatus, total, totalQuantity, bookingValue, prepaidValue, "Holding", Main.SELECTED_CUSTOMER_ID, Main.SELECTED_CUSTOMER_CODE, Main.SELECTED_CUSTOMER_NAME, Main.SELECTED_CUSTOMER_OWNER, Main.SELECTED_CUSTOMER_ADDRESS))

		Dim rsNewOrder As ResultSet = Main.SQLProducts.ExecQuery("SELECT last_insert_rowid() AS id")
		rsNewOrder.NextRow
		Dim newOrderID As Int = rsNewOrder.GetInt("id")
		rsNewOrder.Close

		For Each cartItem As Map In CartItems
			Dim productID As Int = cartItem.Get("product_id")
			Dim unitPrice As Double = cartItem.Get("unit_price")
			Dim quantity As Int = cartItem.Get("quantity")
			Dim paymentStatus As String = GetPaymentStatusFromFulfillmentStatus(FulfillmentStatus)
			Dim deliveryStatus As String = GetDeliveryStatusFromFulfillmentStatus(FulfillmentStatus)

			Main.SQLProducts.ExecNonQuery2( _
                "INSERT INTO order_items (order_id, product_id, quantity, price, fulfillment_status, payment_status, delivery_status) VALUES (?, ?, ?, ?, ?, ?, ?)", _
                Array As Object(newOrderID, productID, quantity, unitPrice, FulfillmentStatus, paymentStatus, deliveryStatus))
		Next

		ApplyStockDeductionFromCart

		Log("Order saved with transaction: " & transactionNumber)

	Catch
		Log("SaveOrderToLocalDatabase error: " & LastException.Message)
		ToastMessageShow("Failed to save order. Please try again.", True)
	End Try
End Sub

Private Sub ApplyStockDeductionFromCart
	Try
		Main.SQLProducts.ExecNonQuery("BEGIN TRANSACTION")

		For Each cartItem As Map In CartItems
			Dim productID As Int = cartItem.Get("product_id")
			Dim quantity As Int = cartItem.Get("quantity")
			Dim remainingStock As Int = GetRemainingStockForProduct(productID)
			If remainingStock < 0 Then Continue

			Main.SQLProducts.ExecNonQuery2( _
				"UPDATE items SET used_stock = IFNULL(used_stock, 0) + ?, remaining_stock = CASE WHEN IFNULL(remaining_stock, 0) - ? < 0 THEN 0 ELSE IFNULL(remaining_stock, 0) - ? END WHERE item_id = ? AND (IFNULL(assigned_stock, 0) > 0 OR IFNULL(used_stock, 0) > 0 OR IFNULL(remaining_stock, 0) > 0)", _
				Array As Object(quantity, quantity, quantity, productID))
		Next

		Main.SQLProducts.ExecNonQuery("COMMIT")
	Catch
		Try
			Main.SQLProducts.ExecNonQuery("ROLLBACK")
		Catch
			Log(LastException.Message)
		End Try
		Log("ApplyStockDeductionFromCart error: " & LastException.Message)
	End Try
End Sub

Private Sub GetCartQuantityForProduct(ProductID As Int) As Int
	Dim totalQuantity As Int = 0
	For Each cartItem As Map In CartItems
		Dim existingProductID As Int = cartItem.Get("product_id")
		If existingProductID = ProductID Then
			totalQuantity = totalQuantity + cartItem.Get("quantity")
		End If
	Next
	Return totalQuantity
End Sub

Private Sub GetRemainingStockForProduct(ProductID As Int) As Int
	If Main.SQLProducts.IsInitialized = False Then Return -1

	Dim rs As ResultSet
	Try
		rs = Main.SQLProducts.ExecQuery2( _
			"SELECT IFNULL(assigned_stock, 0) AS assigned_stock, IFNULL(used_stock, 0) AS used_stock, IFNULL(remaining_stock, 0) AS remaining_stock FROM items WHERE item_id = ?", _
			Array As String(ProductID))

		If rs.NextRow Then
			Dim assignedStock As Int = rs.GetInt("assigned_stock")
			Dim usedStock As Int = rs.GetInt("used_stock")
			Dim remainingStock As Int = rs.GetInt("remaining_stock")
			rs.Close
			If assignedStock <= 0 And usedStock <= 0 And remainingStock <= 0 Then Return -1
			If remainingStock < 0 Then remainingStock = 0
			Return remainingStock
		End If
		rs.Close
	Catch
		If rs.IsInitialized Then rs.Close
		Log("GetRemainingStockForProduct error: " & LastException.Message)
	End Try

	Return -1
End Sub

Private Sub GetBookingFromFulfillmentStatus(FulfillmentStatus As String) As Int
	If FulfillmentStatus.Contains("Booked") Then
		Return 1
	End If
	Return 0
End Sub

Private Sub GetPrepaidFromFulfillmentStatus(FulfillmentStatus As String) As Int
	If FulfillmentStatus.Contains("Paid") And Not(FulfillmentStatus.Contains("NotPaid")) Then
		Return 1
	End If
	Return 0
End Sub

Private Sub GetPaymentStatusFromFulfillmentStatus(FulfillmentStatus As String) As String
	If FulfillmentStatus.Contains("Paid") And Not(FulfillmentStatus.Contains("NotPaid")) Then
		Return "Paid"
	Else
		Return "NotPaid"
	End If
End Sub

Private Sub GetDeliveryStatusFromFulfillmentStatus(FulfillmentStatus As String) As String
	If FulfillmentStatus.Contains("Received") Then
		Return "Received"
	Else
		Return "NotReceived"
	End If
End Sub

Private Sub AddCartItemToList(ProductID As Int, ItemName As String, UnitPrice As Double, Quantity As Int, ItemCode As String)
	Dim availableStock As Int = GetRemainingStockForProduct(ProductID)
	If availableStock >= 0 Then
		Dim currentQuantity As Int = GetCartQuantityForProduct(ProductID)
		If currentQuantity + Quantity > availableStock Then
			ToastMessageShow("Not enough stock left for " & ItemName, True)
			Return
		End If
	End If

	For Each cartItem As Map In CartItems
		Dim existingProductID As Int = cartItem.Get("product_id")
		If existingProductID = ProductID Then
			Dim existingQuantity As Int = cartItem.Get("quantity")
			cartItem.Put("quantity", existingQuantity + Quantity)
			Return
		End If
	Next

	Dim cartItem As Map
	cartItem.Initialize
	cartItem.Put("product_id", ProductID)
	cartItem.Put("item_name", ItemName)
	cartItem.Put("unit_price", UnitPrice)
	cartItem.Put("quantity", Quantity)
	cartItem.Put("item_code", ItemCode)
	CartItems.Add(cartItem)
End Sub


Private Sub ToggleSelection(Index As Int)
	If SelectedIndices.IndexOf(Index) > -1 Then
		SelectedIndices.RemoveAt(SelectedIndices.IndexOf(Index))
		HighlightItem(Index, False)
	Else
		SelectedIndices.Add(Index)
		HighlightItem(Index, True)
	End If

	Dim count As Int = SelectedIndices.Size

	btnDeleteSelected.Text = "Delete (" & count & ")"

	If count > 0 Then
		btnDeleteSelected.Enabled = True
		btnDeleteSelected.Color = Colors.Red
	Else
		btnDeleteSelected.Enabled = False
		btnDeleteSelected.Color = Colors.ARGB(80, 200, 200, 200)
		ExitSelectionMode
	End If
End Sub

Private Sub HighlightItem(Index As Int, Selected As Boolean)
	If Index < 0 Or Index >= clvCartSummary.Size Then Return

	Dim pnl As B4XView = clvCartSummary.GetPanel(Index)

	If Selected Then
		pnl.Color = Colors.LightGray
	Else
		pnl.Color = Colors.White
	End If
End Sub

Private Sub ExitSelectionMode
	SelectionMode = False

	' Remove highlight from all selected indexes
	For Each i As Int In SelectedIndices
		HighlightItem(i, False)
	Next

	SelectedIndices.Clear

	btnDeleteSelected.Enabled = False
	btnDeleteSelected.Color = Colors.ARGB(80, 200, 200, 200)
	btnDeleteSelected.Text = "Delete"
	btnDeleteSelected.Visible = True
End Sub

Private Sub clvCartSummary_ItemLongClick (Index As Int, Value As Object)
	SelectionMode = True
	btnDeleteSelected.Visible = True
	ToggleSelection(Index)
End Sub

Private Sub clvCartSummary_ItemClick (Index As Int, Value As Object)
	If SelectionMode = False Then Return
	ToggleSelection(Index)
End Sub

Private Sub btnCancelSelection_Click
	ExitSelectionMode
End Sub

Private Sub btnDeleteSelected_Click
	' Always allow click, but validate here

	' 1. Check if cart is empty
	If CartItems.Size = 0 Then
		ToastMessageShow("No items to delete", True)
		Return
	End If

	' 2. Check if user selected anything
	If SelectedIndices.Size = 0 Then
		ToastMessageShow("Long press item(s) to select for deletion", True)
		Return
	End If

	' 3. Show confirm delete popup
	PnlConfirmDelete.Visible = True
	PnlConfirmDelete.BringToFront
End Sub

Private Sub btnYesDelete_Click
	' Sort SelectedIndices DESCENDING manually
	For i = 0 To SelectedIndices.Size - 2
		For j = i + 1 To SelectedIndices.Size - 1
			If SelectedIndices.Get(i) < SelectedIndices.Get(j) Then
				Dim temp As Int = SelectedIndices.Get(i)
				SelectedIndices.Set(i, SelectedIndices.Get(j))
				SelectedIndices.Set(j, temp)
			End If
		Next
	Next

	' Now delete safely
	For Each index As Int In SelectedIndices
		If index >= 0 And index < CartItems.Size Then
			CartItems.RemoveAt(index)
		End If
	Next

	SelectedIndices.Clear
	RefreshCartDisplay

	PnlConfirmDelete.Visible = False
	btnDeleteSelected.Enabled = False
	btnDeleteSelected.Color = Colors.ARGB(80, 200, 200, 200)
	btnDeleteSelected.Text = "Delete"
	ExitSelectionMode
End Sub

Private Sub btnNoDelete_Click
	PnlConfirmDelete.Visible = False

End Sub


