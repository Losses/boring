package org.tiqian.protocol;

class TableData {
    public var replayStringCount:Int;
    public var strings:Array<String>;
    public var metricRows:Array<MetricEntry>;
    public var valuePool:Array<ValueRow>;
    public var probeTextRefs:Array<Int>;
    public var probeAdvanceRefs:Array<Int>;
    public var probeStyleRefs:Array<Int>;
    public var probeFeatureRefs:Array<Int>;
    public var advancePool:Array<Float>;
    public var styleFontSize:Array<Float>;
    public var styleFontWeight:Array<Float>;
    public var styleItalic:Array<Int>;
    public var styleScriptRefs:Array<Int>;
    public var styleLanguageRefs:Array<Int>;
    public var featuresPool:Array<Array<Int>>;
    public var faceTexts:Array<String>;
    public var typographyTexts:Array<String>;
    public var valueStyleTexts:Array<String>;
    public var fontPreloadTexts:Array<String>;
    public var revisionText:String;

    public function new() {
        replayStringCount = 0;
        strings = new Array<String>();
        metricRows = new Array<MetricEntry>();
        valuePool = new Array<ValueRow>();
        probeTextRefs = new Array<Int>();
        probeAdvanceRefs = new Array<Int>();
        probeStyleRefs = new Array<Int>();
        probeFeatureRefs = new Array<Int>();
        advancePool = new Array<Float>();
        styleFontSize = new Array<Float>();
        styleFontWeight = new Array<Float>();
        styleItalic = new Array<Int>();
        styleScriptRefs = new Array<Int>();
        styleLanguageRefs = new Array<Int>();
        featuresPool = new Array<Array<Int>>();
        faceTexts = new Array<String>();
        typographyTexts = new Array<String>();
        valueStyleTexts = new Array<String>();
        fontPreloadTexts = new Array<String>();
        revisionText = "";
    }
}

