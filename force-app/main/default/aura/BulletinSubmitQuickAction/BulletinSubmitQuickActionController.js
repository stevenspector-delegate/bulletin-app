({
    handleSuccess : function(component, event, helper) {
        var toast = $A.get("e.force:showToast");
        $A.get("e.force:closeQuickAction").fire();
    },
    handleClose : function(component, event, helper) {
        $A.get("e.force:closeQuickAction").fire();
    }
})
