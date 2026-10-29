package org.tiqian.protocol;

class TableInput {
    public var replayStrings:Array<String>;
    public var metrics:Array<TableMetricRow>;
    public var probes:Array<TableProbe>;
    public var faces:Array<String>;
    public var typographies:Array<String>;
    public var valueStyles:Array<String>;
    public var fontPreloads:Array<String>;
    public var revisionsText:String;

    public function new(replayStrings:Array<String>, metrics:Array<TableMetricRow>, probes:Array<TableProbe>,
            faces:Array<String>, typographies:Array<String>, valueStyles:Array<String>,
            fontPreloads:Array<String>, revisionsText:String) {
        this.replayStrings = replayStrings;
        this.metrics = metrics;
        this.probes = probes;
        this.faces = faces;
        this.typographies = typographies;
        this.valueStyles = valueStyles;
        this.fontPreloads = fontPreloads;
        this.revisionsText = revisionsText;
    }
}

/** One semantic metric row; valuesEm carries exactly five slots. */
