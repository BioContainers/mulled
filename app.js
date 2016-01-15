(function () {
  var xmlhttp = new XMLHttpRequest();

  xmlhttp.onreadystatechange = function() {
    if (xmlhttp.readyState == XMLHttpRequest.DONE ) {
      if(xmlhttp.status == 200){
        var data = JSON.parse(xmlhttp.responseText);
        renderData(data);
      } else {
        console.log(xmlhttp);
      }
    }
  }

  xmlhttp.open("GET", "/api/v1/images.json");
  xmlhttp.send();

  function renderData(data) {
    var c = document.querySelector("#package-card").content;

    var par = document.querySelector(".card-columns");
    data.forEach(function (p) {
      c.querySelector("h3.card-title").innerText = p.image;
      c.querySelector("h6.card-subtitle").innerText = p.version + " via " + p.packager;
      c.querySelector("p.card-text span").innerText = p.description;
      c.querySelector("a.package-homepage").href = p.homepage;
      c.querySelector("a.package-homepage").innerText = p.homepage;
      c.querySelector("input").value = "quay.io/mulled/"  + p.image + "@" + p.checksum;
      c.querySelector("button.copy-btn").setAttribute('data-clipboard-text', "docker run -it --rm quay.io/mulled/"  + p.image + "@" + p.checksum);

      c.querySelector("span.package-size").innerText = p.size;
      c.querySelector("span.package-date").innerText = new Date(p.date).toLocaleString();
      c.querySelector("a.build-url").href = p.buildurl;

      c.querySelector("a.report-bug").href = "https://github.com/thriqon/mulled/issues/new?labels=bug&title=[" + p.image + "] Bug:";

      var n = document.importNode(c, true);
      par.appendChild(n);
    });

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
  }
}());
