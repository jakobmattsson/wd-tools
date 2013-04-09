chai = require 'chai'
steps = require '../lib/wd-tools'
expect = chai.expect


describe "makeExpression", ->

  it "parses the empty string", ->
    expect(steps.makeExpression("")).to.eql [
      { selector: "" }
    ]

  it "parses a css selector", ->
    expect(steps.makeExpression(".current-tab-pane")).to.eql [
      { selector: ".current-tab-pane" }
    ]

  it "parses a nested css selector", ->
    expect(steps.makeExpression(".current-tab-pane input apa")).to.eql [
      { selector: ".current-tab-pane input apa" }
    ]

  it "parses a css selector with a meta tag", ->
    expect(steps.makeExpression(".current-tab-pane input{text:'first device'} apa")).to.eql [
      { selector: ".current-tab-pane input", meta: { text: 'first device' } }
      { selector: 'apa' }
    ]

  it "parses several css selector with several meta tags", ->
    expect(steps.makeExpression(".current-tab-pane input{text:'first device'} apa{prop:'4'}")).to.eql [
      { selector: ".current-tab-pane input", meta: { text: 'first device' } }
      { selector: 'apa', meta: { prop: '4' } }
    ]

  it "ignores extra whitespace", ->
    expect(steps.makeExpression("div  {  text  :  'first device'  }  x")).to.eql [
      { selector: "div", meta: { text: 'first device' } }
      { selector: 'x' }
    ]

  it "accepts matchers that are regexps", ->
    expect(steps.makeExpression("div  {  text  :  /first device/  }  x")).to.eql [
      { selector: "div", meta: { text: /first device/ } }
      { selector: 'x' }
    ]

  it "accepts matchers wrapped in functions", ->
    expect(steps.makeExpression("div {text:something('first device')} x")).to.eql [
      { selector: "div", meta: { text: { something: 'first device' } } }
      { selector: 'x' }
    ]

  it "accepts matchers wrapped in functions, with lots of whitespace", ->
    expect(steps.makeExpression("div {  text  :  dark  (  'first device'  )  } x")).to.eql [
      { selector: "div", meta: { text: { dark: 'first device' } } }
      { selector: 'x' }
    ]

  it "accepts colons as string arguments", ->
    expect(steps.makeExpression("div {text:something('first: device')} x")).to.eql [
      { selector: "div", meta: { text: { something: 'first: device' } } }
      { selector: 'x' }
    ]
