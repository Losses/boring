package org.tiqian.protocol;

/**
 * One semantic attribute of an Inline node, a name/value pair carried in
 * the order the semantic tag declares them (protocol 5.2, 5.5).
 */
typedef LayoutAttribute = {
    final name:String;
    final value:String;
}
