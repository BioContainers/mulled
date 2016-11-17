---
---

(function () {
  var xmlhttp = new XMLHttpRequest();

  xmlhttp.onreadystatechange = function() {
    if (xmlhttp.readyState == XMLHttpRequest.DONE ) {
      if(xmlhttp.status == 200){
        var data = JSON.parse(xmlhttp.responseText);
        renderData(data.packages);
      } else {
        console.log(xmlhttp);
      }
    }
  }

  xmlhttp.open("GET", "v2/images.json");
  xmlhttp.send();

  function renderData(data) {
    var c = document.querySelector("#package-card").content;
    var vt = document.querySelector("#package-version").content;

    var par = document.querySelector(".card-columns");
    data.forEach(function (p) {
      c.querySelector("h3.card-title").textContent = p.id;
      c.querySelector("h6.card-subtitle").textContent = "via " + p.packager;
      c.querySelector("blockquote p").textContent = p.description;
      c.querySelector("a.package-homepage").href = p.homepage;
      c.querySelector("a.package-homepage").textContent = p.homepage;


      var card = c.querySelector(".card");
      Array.prototype.forEach.call(c.querySelectorAll(".card .package-version"), function (c) {
        card.removeChild(c);
      });

      p.versions.forEach(function (ver) {
        vt.querySelector("h4").textContent = ver.version;
        vt.querySelector("button.copy-btn").setAttribute("data-clipboard-text", "docker run -it --rm quay.io/biocontainers/" + p.id + ":" + ver.revision);
        vt.querySelector("span.package-size").textContent = numeral(ver.size).format('0b');
        vt.querySelector("span.package-date").textContent = new Date(ver.date).toLocaleString();

				vt.querySelector("a.build-url").href = ver.buildurl;


        var n = document.importNode(vt, true);
        c.querySelector(".card").appendChild(n);
      });

			c.querySelector("a.report-bug").href = "{{site.github.issues_url}}/new?labels=bug&title=[" + p.id + "] Bug:";

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
