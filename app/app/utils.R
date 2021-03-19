
news2_pulse <- function(x) {
  "convert from pulse (real) to news score"
  assertNumeric(x)
  r <- data.table(x=x, y=0L)
  r[, y := ifelse(x <= 50 | x >= 91, 1L, y )]
  r[, y := ifelse(x >= 111, 2L, y )]
  r[, y := ifelse(x <= 40 | x >= 131, 3L, y )]
  return(r$y)
}