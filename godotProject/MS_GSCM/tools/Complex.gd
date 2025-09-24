class_name Complex

var re: float
var im: float

func _init(r: float, i: float = 0.0):
	re = r
	im = i

func add(other: Complex) -> Complex:
	return Complex.new(re + other.re, im + other.im)

func sub(other: Complex) -> Complex:
	return Complex.new(re - other.re, im - other.im)

func mul(other: Complex) -> Complex:
	return Complex.new(re * other.re - im * other.im, re * other.im + im * other.re)

func div(other: Complex) -> Complex:
	var denom = other.re * other.re + other.im * other.im
	return Complex.new((re * other.re + im * other.im) / denom, (im * other.re - re * other.im) / denom)

func mul_real(val: float) -> Complex:
	return Complex.new(re * val, im * val)


func abs() -> float:
	return sqrt(re * re + im * im)

func conj() -> Complex:
	return Complex.new(re, -im)

func to_str() -> String:
	var sign = "+" if im >= 0 else ""
	return str(re) + sign + str(im) + "j"
func sub_real(val: float) -> Complex:
	return Complex.new(re - val, im)

func pow_real(exponent: float) -> Complex:
	var r = self.abs()
	var theta = atan2(im, re)
	var new_r = pow(r, exponent)
	var new_theta = theta * exponent
	return Complex.new(new_r * cos(new_theta), new_r * sin(new_theta))
#func sqrt() -> Complex:
	#return pow_real(0.5)
