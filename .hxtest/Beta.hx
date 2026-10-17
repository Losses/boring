import Alpha.AlphaColor;
import Alpha.AlphaMood;

class Beta {
  static function go(c:AlphaColor, m:AlphaMood):String {
    return switch [c, m] {
      case [Red, Happy]: "red-happy";
      case [Green, _]: "green";
      case _: "other";
    };
  }
  static function main() {
    trace(go(Red, Happy));
    trace(go(Green, Sad));
  }
}
