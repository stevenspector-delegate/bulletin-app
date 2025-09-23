({
  openModal: function (cmp) {
    $A.createComponent("c:bulletinSubmitModalBody", {}, function (bodyCmp, status) {
      if (status === "SUCCESS") {
        cmp.find("overlayLib").showCustomModal({
          header: "New Bulletin Request",
          body: bodyCmp,
          showCloseButton: true,
          cssClass: "slds-modal_large",
          closeCallback: function () {
            var evt = $A.get("e.force:closeQuickAction");
            if (evt) evt.fire(); // <- closes the global action panel
          }
        }).then(function (overlay) {
          cmp.set("v.overlayRef", overlay);
          bodyCmp.set("v.overlayRef", overlay);
        });
      }
    });
  }
})
