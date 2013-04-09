RealJSON [![Build Status](https://secure.travis-ci.org/jakobmattsson/wd-tools.png)](http://travis-ci.org/jakobmattsson/wd-tools)
========

Utility functions for Selenium WebDriver.



Installation
------------

`npm install wd-tools`



Usage
-----

    var browser = require('wd').remote();
    var wdTools = require('wd-tools');
    wdTools.getSingleElement(browser, '.some-class', function(err, element) {
      console.log(element);
    });
