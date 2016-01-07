
(function () {
  var selector = '.copy-btn';

  var pushCommandCopyButtons = new Clipboard(selector);

  pushCommandCopyButtons.on('success', function (e) {
    showTooltip(e.trigger, 'Copied!');
  });

  pushCommandCopyButtons.on('error', function (e) {
    console.log(e);
    showTooltip(e.trigger, 'Error');
  });


  function showTooltip(node, text) {
    var tooltipNode = document.createElement('div');
    tooltipNode.setAttribute('class', 'tooltip in');
    tooltipNode.setAttribute('role', 'tooltip');
    var innerNode = document.createElement('div');
    innerNode.setAttribute('class', 'tooltip-inner');
    innerNode.appendChild(document.createTextNode('Copied!'));
    tooltipNode.appendChild(innerNode);

    document.body.appendChild(tooltipNode);
    moveBelow(node, tooltipNode);

    node.addEventListener('mouseleave', function leaveHandler(e) {
      node.removeEventListener('mouseleave', leaveHandler);
      setTimeout(function () {
        document.body.removeChild(tooltipNode);
      }, 250);
    });

  }

  function moveBelow(ref, node) {
    var refleft = reftop = 0;

    reftop += ref.clientHeight + 7;

    if (ref.offsetParent) {
      do {
        refleft += ref.offsetLeft;
        reftop += ref.offsetTop;
      } while (ref = ref.offsetParent);
    }


    node.setAttribute('style', 'position: absolute; left: ' + refleft + 'px; top: ' + reftop + 'px');
  }
}());
