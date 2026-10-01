// 准入探针 B（任务 t-mum0wts5-jh3m）：coalescing default 的默认表达式 E
// 是可抛静态调用（同文件内 throwingG，seed 超阈值抛枚举承载异常）。
// 预期：被接受（rc=0，空输出）：spec 22 Stage-A static-call 语法根不检查
// 被调函数的 fallibility，DefaultArgExpander.validateCoalescingGrammar 规则 6
// 纯语法判定。main 省略 value 实参触发默认求值。
// 编译命令见 run.sh 的 admit-coalescing-throwing 阶段。
enum ProbeFault {
	OverLimit(seed:Int);
}

class ProbeException extends haxe.Exception {
	public final fault:ProbeFault;

	public function new(fault:ProbeFault) {
		this.fault = fault;
		super(switch (fault) {
			case OverLimit(seed): 'over limit: $seed';
		});
	}
}

class PCoalescingThrowing {
	static function main() {
		use(1);
	}

	static function throwingG(seed:Int):Int {
		if (seed > 10) {
			throw new ProbeException(OverLimit(seed));
		}
		return seed * 2;
	}

	static function use(seed:Int, ?value:Int):Int {
		var normalized = value == null ? throwingG(seed) : value;
		return normalized;
	}
}
