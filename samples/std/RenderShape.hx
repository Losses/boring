package std;

/**
 * Cross-package interface consumed by a boring-side implementing class.
 * Lives in the std package like the other stdlib faces; the implementing
 * class and the call site live in the business package.
 */
interface RenderShape {
    function render(text:String):String;
}
