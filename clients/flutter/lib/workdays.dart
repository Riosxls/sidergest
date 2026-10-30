/// Working-day calendar for delivery lead times ("prazo de entrega em dias úteis").
///
/// A working day is Monday to Friday that is not a national holiday. State and municipal holidays are
/// not known here. Keep in sync with `Ebt.Core/Services/WorkDays.cs`, which the server uses for the same math.
library;

DateTime _easter(int year) {
  final a = year % 19, b = year ~/ 100, c = year % 100;
  final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

final _holidayCache = <int, Set<DateTime>>{};

/// National holidays of [year] (fixed dates plus Good Friday).
Set<DateTime> nationalHolidays(int year) => _holidayCache.putIfAbsent(year, () {
  final goodFriday = _easter(year).subtract(const Duration(days: 2));
  return {
    DateTime(year, 1, 1), // Confraternização Universal
    DateTime(goodFriday.year, goodFriday.month, goodFriday.day), // Sexta-feira Santa
    DateTime(year, 4, 21), // Tiradentes
    DateTime(year, 5, 1), // Dia do Trabalho
    DateTime(year, 9, 7), // Independência
    DateTime(year, 10, 12), // Nossa Senhora Aparecida
    DateTime(year, 11, 2), // Finados
    DateTime(year, 11, 15), // Proclamação da República
    if (year >= 2024) DateTime(year, 11, 20), // Consciência Negra
    DateTime(year, 12, 25), // Natal
  };
});

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool isWorkDay(DateTime d) {
  final day = _day(d);
  return day.weekday < DateTime.saturday && !nationalHolidays(day.year).contains(day);
}

DateTime _next(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// The date [days] working days after [start] (day 0 is [start] itself, whatever kind of day it is).
DateTime addWorkDays(DateTime start, int days) {
  var d = _day(start);
  var left = days;
  while (left > 0) {
    d = _next(d);
    if (isWorkDay(d)) left--;
  }
  return d;
}

/// Working days after [start] up to and including [end]; 0 when [end] is not after [start].
int workDaysBetween(DateTime start, DateTime end) {
  var d = _day(start);
  final stop = _day(end);
  var n = 0;
  while (d.isBefore(stop)) {
    d = _next(d);
    if (isWorkDay(d)) n++;
  }
  return n;
}
