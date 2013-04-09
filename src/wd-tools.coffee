nodeUrl = require 'url'
async = require 'async'
_ = require 'underscore'


propagate = (callback, onSuccess) ->
  (err, rest...) ->
    return callback(err) if err
    onSuccess(rest...)


seleniumError = (err, regex) -> err?.cause?.value?.message.match(regex)?
notFoundErr = (err) -> seleniumError(err, /^Could not find element/)
noLongerInDOM = (err) -> seleniumError(err, /^Error Message => 'Element is no longer attached to the DOM/) || seleniumError(err, /^Element is no longer attached to the DOM/)
notDisplayedErr = (err) -> seleniumError(err, /^Element must be displayed to click/)

selectorToClickList = (selectorExtra) ->
  list = _.flatten selectorExtra.split(':text').map (x, i) -> if i == 0 then x else x.slice(2).split("')")
  list.map (x, i) -> if x.trim() == '' then null else x.trim()


multipleSelectorResolver = (baseList, sel, callback) ->
  async.map baseList, (e, callback) ->
    e.elementsByCssSelector sel, (err, elements) ->
      if noLongerInDOM(err)
        callback(null, [])
      else
        callback(err, elements)
  , propagate callback, (hits) ->
    callback(null, _.flatten(hits))


gnjom = (newList, tag, funcName, callback) ->
  errors = []
  async.filter newList, (e, cb) ->
    e[funcName] (err, textContent) ->
      if noLongerInDOM(err)
        cb(false)
      else if err
        errors.push(err)
        cb(false)
      else if _.isString(tag)
        cb(textContent == tag)
      else if _.isRegExp(tag)
        errors.push("not implemented")
        cb(false)
      else if Object.keys(tag).length == 1 && tag.contains?
        cb(textContent && textContent.indexOf(tag.contains) != -1)
      else
        errors.push("what do you want?!")
        cb(false)
  , (elems) ->
    return callback(errors[0]) if errors.length > 0
    callback(null, elems)



resolver = (baseList, sel, callback) ->
  multipleSelectorResolver baseList, sel.selector, propagate callback, (newList) ->
    return callback(null, newList) if !sel.meta

    if Object.keys(sel.meta).length == 1 && sel.meta.text?
      gnjom(newList, sel.meta.text, 'text', callback)
    else if Object.keys(sel.meta).length == 1 && sel.meta.value?
      gnjom(newList, sel.meta.value, 'getValue', callback)
    else if Object.keys(sel.meta).length == 1 && sel.meta.index?
      callback(null, newList.filter((x, i) -> i.toString() == sel.meta.index))
    else
      throw "dont know what to do"



listResolver = (baseList, sels, callback) ->
  async.reduce sels, baseList, resolver, callback



exports.makeExpression = makeExpression = (str) ->
  str = str.trim()
  hits = str.match /^([^{]*)({[^}]*})?/

  throw "fail" if !hits?

  m = { selector: hits[1]?.trim() }
  if hits[2]?
    [key, val...] = hits[2].slice(1, -1).split(':')
    value = val.join(':')

    key = key?.trim()
    value = value?.trim()

    if value.slice(0, 1) == '/' && value.slice(-1) == '/'
      value = new RegExp(value.slice(1, -1))
      m.meta = {}
      m.meta[key] = value
    else if value.slice(0, 1) == "'" && value.slice(-1) == "'"
      value = '"' + value.slice(1, -1) + '"'
      m.meta = {}
      m.meta[key] = JSON.parse(value)
    else
      match = value.match(/^([_a-zA-Z0-9]+)\s*\(\s*'([^']*)'\s*\)$/)
      throw new Error("Invalid expression selector") if !match?

      [fullmatch, funcName, argName] = match
      m.meta = {}
      m.meta[key] = {}
      m.meta[key][funcName] = argName

  prefix = hits[1] + (hits[2] || '')

  if prefix.length < str.length
    [m].concat(makeExpression(str.slice(prefix.length)))
  else
    [m]



exports.resolveUrl = resolveUrl = (browser, url, callback) ->
  if url[0] == '/'
    browser.url propagate callback, (current) ->
      {protocol,host} = nodeUrl.parse(current)
      nUrl = protocol + '//' + host + url
      callback(null, nUrl)
  else
    callback(null, url)

exports.getElements = getElements = (browser, selector, callback) ->
  exp = makeExpression(selector)
  listResolver([browser], exp, callback)

exports.getVisibleElements = getVisibleElements = (browser, selector, callback) ->
  exp = makeExpression(selector)
  listResolver [browser], exp, propagate callback, (elements) ->
    async.filter elements, (e, callback) ->
      e.isVisible (err, visible) -> callback(!err? && visible)
    , (visibleElements) ->
      callback(null, visibleElements)

exports.getVisibleElementsUntil = getVisibleElementsUntil = (browser, selector, predicate, callback) ->
  attempt = (counter) ->
    getVisibleElements browser, selector, propagate callback, (elements) ->
      if !predicate(elements) && counter > 0
        setTimeout ->
          attempt(counter-1)
        , 100
      else
        callback(null, elements)
  attempt(50)

exports.getElementsUntil = getElementsUntil = (browser, selector, predicate, callback) ->
  attempt = (counter) ->
    getElements browser, selector, propagate callback, (elements) ->
      if !predicate(elements) && counter > 0
        setTimeout ->
          attempt(counter-1)
        , 100
      else
        callback(null, elements)
  attempt(50)

exports.getSingleElement = getSingleElement = (browser, selector, callback) ->
  getElementsUntil browser, selector, ((elements) -> elements.length == 1), (err, elements) ->
    if err?
      callback(err)
    else if elements.length == 0
      callback(new Error("no matches"))
    else if elements.length > 1
      callback(new Error("ambigious: " + selector + " matched " + elements.length + " elements"))
    else
      callback(null, elements[0])



exports.hoverClick = (browser, browserName, hoverSelector, clickSelector, callback) ->

  clickSe = makeExpression(clickSelector)

  str = """
    (function() {

      var multipleSelectorResolver = function(baseList, selector) {
        return Array.prototype.concat.apply([], baseList.map(function(m) {
          return Array.prototype.slice.call(m.querySelectorAll(selector), 0);
        }));
      };

      var isRegExp = function(x) {
        return Object.prototype.toString.call(x) == '[object RegExp]';
      };

      var gnjoma = function(newList, tag, eToVal) {
        return newList.filter(function(e) {
          var content = eToVal(e);
          if (typeof tag == 'string') {
            return content == tag;
          } else if (isRegExp(tag)) {
            throw "not implemented";
          } else if (Object.keys(tag).length == 1 && typeof tag.contains != 'undefined') {
            return content != null && content.indexOf(tag.contains) !== -1;
          } else {
            throw "what do you want?!";
          }
        });
      };

      var resolver = function(baseList, sel) {
        var newList = multipleSelectorResolver(baseList, sel.selector);
        if (!sel.meta) {
          return newList;
        } else if (Object.keys(sel.meta).length === 1 && sel.meta.text) {
          return gnjoma(newList, sel.meta.text, function(e) { return e.innerText || e.textContent; });
        } else if (Object.keys(sel.meta).length === 1 && sel.meta.value) {
          return gnjoma(newList, sel.meta.value, function(e) { return e.value; });
        } else {
          throw "WAT";
        }
      };

      var getElements = function(expression) {
        return expression.reduce(resolver, [document]);
      };

      var getSingleElement = function(expression, callback) {
        var attemptGet = function(attempts) {
          var elements = getElements(expression);
          if (elements.length == 1) {
            callback(null, elements[0]);
          } else {
            if (attempts == 0) {
              if (elements.length == 0) {
                callback(new Error("no matches"));
              } else if (elements.length > 1) {
                callback(new Error("ambigious: " + selector + " matched " + elements.length + " elements"));
              }
            } else {
              setTimeout(function() {
                attemptGet(attempts-1);
              }, 100);
            }
          }
        };
        attemptGet(50);
      };

      var list = #{JSON.stringify(clickSe)};

      getSingleElement(list, function(err, element) {
        if (err) {
          throw err;
        }
        element.click();
      });
    }());
  """

  if browserName == 'firefox' || browserName == 'safari' || browserName == 'chrome'
    browser.eval(str, callback)
  else
    getSingleElement browser, hoverSelector, propagate callback, (element) ->
      browser.moveTo element, propagate callback, ->
        getSingleElement browser, clickSelector, propagate callback, (element) ->
          element.click(callback)

exports.checkUrlPredicate = (browser, predicate, callback) ->
  check = (url, cnt) ->
    if predicate(url)
      callback(true, url)
    else
      if cnt == 0
        callback(false, url)
      else
        setTimeout ->
          attempt(cnt-1)
        , 100

  attempt = (cnt) =>
    browser.url propagate callback, (currentUrl) ->
      check(currentUrl, cnt)

  attempt(50)


exports.goto = (browser, destinationUrl, callback) ->
  resolveUrl browser, destinationUrl, propagate callback, (resolvedDestinationUrl) =>
    browser.url propagate callback, (currentUrl) ->
      if currentUrl == resolvedDestinationUrl
        browser.refresh(callback)
      else
        browser.get resolvedDestinationUrl, callback

exports.getElementWidths = (browser, selector, callback) ->
  getElements browser, selector, propagate callback, (elements) ->
    async.map elements, (e, callback) ->
      e.getComputedCss 'width', (err, value) ->
        match = value.match('(.*)px')
        if err
          callback(err)
        else if !match
          callback("Invalid format")
        else
          callback(null, parseFloat(match[1]))
    , callback
