({
  closeAll: function(cmp){
    var overlay = cmp.get("v.overlayRef");
    if (overlay) overlay.close();
  }
})
