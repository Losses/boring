// 准入探针 A（任务 t-mum0wts5-jh3m）：默认位直接放调用。
// 预期：被拒绝，具名错误 default argument values accept compile-time
// constants only（spec 22 规则 1 / style standard V16 NonConstantDefault 行）。
// 编译命令见 run.sh 的 admit-default-position 阶段（完整管线：
// -lib reflaxe -lib boring + Intercept.run）。
class PDefaultPosition {
	static function main() {
		use(1);
	}

	static function g(x:Int):Int {
		return x * 2;
	}

	static function use(p:Int = g(2)):Int {
		return p;
	}
}
