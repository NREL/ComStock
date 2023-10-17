var frameworksOrder = ['javascript', 'pdfkit'];
var frameworksLabels = {
  'javascript': 'JavaScript',
  'pdfkit': 'PDFkit'
};
var preferredFramework = 'javascript';
var activeFile;
var samplesHash = {};
var files = [{
  label: 'Workflow',
  items: [{
    label: 'ComStock Workflow Vertical with Nodes',
    frameworks: {
      javascript: 'views/ComStock_nodes.html',
      pdfkit: 'pdf/ComStock.html'
    }
  }, {
    label: 'ComStock Workflow Horizontal with Labels',
    frameworks: {
      javascript: 'views/ComStock_horizontal.html',
      pdfkit: 'pdf/ComStock_left.html'
    }
  }, {
    label: 'ComStock Workflow Vertical with Labels',
    frameworks: {
      javascript: 'views/ComStock_vertical.html',
      pdfkit: 'pdf/ComStock.html'
    }
  }]
}];

document.addEventListener('DOMContentLoaded', function () {
  // build samples hash
  samplesHash = {};
  for (var index = 0; index < files.length; index += 1) {
    var optgroup = files[index];
    for (var itemIndex = 0; itemIndex < optgroup.items.length; itemIndex += 1) {
      var option = optgroup.items[itemIndex];
      var key = index + '-' + itemIndex;
      samplesHash[key] = option;
      if (activeFile === undefined) {
        activeFile = option;
      }
    }
  }

  updateFiles(activeFile);
  preferredFramework = updateFrameworks(activeFile.frameworks, preferredFramework);
  resizeWindow();
  Update();

  var filesElement = document.getElementById('files');
  filesElement.addEventListener('change', function (event) {
    var filesElement = document.getElementById('files');
    activeFile = samplesHash[filesElement.options[filesElement.selectedIndex].getAttribute('data-key')];
    preferredFramework = updateFrameworks(activeFile.frameworks, preferredFramework);
    Update();
  });


  var frameworksElement = document.getElementById('frameworks');
  frameworksElement.addEventListener('click', function (event) {
    preferredFramework = event.target.getAttribute('id');
    preferredFramework = updateFrameworks(activeFile.frameworks, preferredFramework);
    Update();
  });

  var openUrlElement = document.getElementById('openURL');
  openUrlElement.addEventListener('click', function (event) {
    var frameworkUrl = activeFile.frameworks[preferredFramework];
    window.location.href = frameworkUrl;
  });

  window.addEventListener('resize', function (event) {
    resizeWindow();
  });
});

function resizeWindow() {
  var navigationBarElement = document.getElementById('navigationBar');
  var frameworksBarElement = document.getElementById('frameworksBar');
  var placeholderElement = document.getElementById('placeholder');
  placeholderElement.style.top = (navigationBarElement.offsetHeight + frameworksBarElement.offsetHeight) + 'px';
}

function Update() {
  var frameworkUrl = activeFile.frameworks[preferredFramework];
  var contentElement = document.getElementById('content');
  contentElement.setAttribute('src', frameworkUrl);
}

function updateFiles(activeFile) {
  var activeFile;
  var filesElement = document.getElementById('files');
  filesElement.innerHTML = '';
  for (var index = 0; index < files.length; index += 1) {
    var optgroup = files[index];
    var optgroupElement = document.createElement('OPTGROUP');
    optgroupElement.setAttribute('label', optgroup.label);

    for (var itemIndex = 0; itemIndex < optgroup.items.length; itemIndex += 1) {
      var option = optgroup.items[itemIndex];
      var optionElement = document.createElement('OPTION');
      var key = index + '-' + itemIndex;
      optionElement.setAttribute('data-key', key);
      optionElement.appendChild(document.createTextNode(option.label));
      optgroupElement.appendChild(optionElement);
    }
    filesElement.appendChild(optgroupElement);
  }
}

function updateFrameworks(frameworks, preferredFramework) {
  if (!frameworks.hasOwnProperty(preferredFramework)) {
    for (var index = 0; index < frameworksOrder.length; index += 1) {
      var framework = frameworksOrder[index];
      if (frameworks[framework] !== undefined) {
        preferredFramework = framework;
      }
    }
  }

  var frameworksElement = document.getElementById('frameworks');
  frameworksElement.innerHTML = '';
  for (var index = 0; index < frameworksOrder.length; index += 1) {
    var framework = frameworksOrder[index];
    var frameworkElement = document.createElement('li');
    frameworkElement.setAttribute('class', 'nav-item');
    frameworkElement.setAttribute('id', framework);
    frameworkElement.setAttribute('value', framework);
    var hrefElement = document.createElement('a');
    hrefElement.setAttribute('class', 'nav-link' + (framework === preferredFramework ? ' active' : '') + (frameworks[framework] === undefined ? ' disabled' : ''));
    hrefElement.setAttribute('id', framework);
    hrefElement.setAttribute('value', framework);
    hrefElement.setAttribute('href', '#');
    hrefElement.appendChild(document.createTextNode(frameworksLabels[framework]));
    frameworkElement.appendChild(hrefElement);
    frameworksElement.appendChild(frameworkElement);
  }
  return preferredFramework;
}
