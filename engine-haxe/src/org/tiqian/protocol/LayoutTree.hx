package org.tiqian.protocol;

/**
 * The platform-neutral Layout Tree node union, the single source of
 * block-level structure shared by the Compose and Apple renderers
 * (protocol 5.2). A Block is a block-level container laid out once; an
 * Inline carries its semantic tag plus attributes and its four inline
 * configurations; a Float is a future positioned shape kept out of the
 * layout path for now.
 */
enum LayoutTree {
    Block(children:Array<LayoutTree>);
    Inline(tagName:Null<String>, attributes:Array<LayoutAttribute>,
        continueAdjacent:Bool, wordBreakable:Bool, lineBreakable:Bool,
        text:String, children:Array<LayoutTree>);
    Float(x:Float, y:Float, shape:LayoutFloatShape);
}
