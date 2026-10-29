package org.tiqian.protocol;

/**
 * The shape of a Float node: a circle, a square, or a polygon
 * (protocol 5.2). Vertices are layout coordinates in document order.
 */
enum LayoutFloatShape {
    Circle(radius:Float);
    Square(side:Float);
    Polygon(vertices:Array<LayoutVertex>);
}
