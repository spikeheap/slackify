// delete collector button
$( "a[data-collector-id]" ).click(function() {
  collectorId = $(this).attr("data-collector-id")
  $.ajax({
      url: '/collectors/' + collectorId,
      type: 'DELETE',
      success: function(result) {
        console.log('DELETE result', result);
      },
      error: function(result) {
        console.log('Error trying to delete', result);
      },
  });
});

// Log out button
$( "a[data-action='logout']" ).click(function() {
  $.ajax({
      url: '/session',
      type: 'DELETE',
      success: function(result) {
        location.reload(true);
      },
      error: function(result) {
        console.log('Error trying to log out', result);
      },
  });
});
