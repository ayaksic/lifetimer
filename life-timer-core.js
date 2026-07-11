(function (root, factory) {
  const core = factory();
  if (typeof module === "object" && module.exports) module.exports = core;
  root.LifeTimerWebCore = core;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const periodNames = ["hour", "day", "week", "month", "year", "lifetime"];
  const numberFormatter = new Intl.NumberFormat("en-US");
  const unitDurations = {
    week: 7 * 24 * 60 * 60 * 1000,
    day: 24 * 60 * 60 * 1000,
    hour: 60 * 60 * 1000,
  };

  function normalizePeriod(period) {
    return typeof period === "number" ? periodNames[period] : period;
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function cloneDate(date) {
    return new Date(date.getTime());
  }

  function addYears(date, years) {
    return new Date(
      date.getFullYear() + years,
      date.getMonth(),
      date.getDate(),
      date.getHours(),
      date.getMinutes(),
      date.getSeconds(),
      date.getMilliseconds(),
    );
  }

  function addMonths(date, months) {
    return new Date(
      date.getFullYear(),
      date.getMonth() + months,
      date.getDate(),
      date.getHours(),
      date.getMinutes(),
      date.getSeconds(),
      date.getMilliseconds(),
    );
  }

  function range(periodValue, now, lifetimeStart) {
    const period = normalizePeriod(periodValue);
    let start;
    let end;

    switch (period) {
      case "hour":
        start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours());
        end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1);
        break;
      case "day":
        start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        break;
      case "week":
        start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay());
        end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7);
        break;
      case "month":
        start = new Date(now.getFullYear(), now.getMonth(), 1);
        end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
        break;
      case "year":
        start = new Date(now.getFullYear(), 0, 1);
        end = new Date(now.getFullYear() + 1, 0, 1);
        break;
      case "lifetime":
        start = cloneDate(lifetimeStart);
        end = addYears(lifetimeStart, 80);
        break;
      default:
        throw new Error(`Unsupported Life Timer period: ${period}`);
    }

    return { start, end };
  }

  function progress(period, now, lifetimeStart) {
    const interval = range(period, now, lifetimeStart);
    return clamp((now - interval.start) / (interval.end - interval.start), 0, 1);
  }

  function formatUnitPosition(current, total) {
    return `${numberFormatter.format(current)}/${numberFormatter.format(total)}`;
  }

  function calendarTime(date) {
    return Date.UTC(
      date.getFullYear(),
      date.getMonth(),
      date.getDate(),
      date.getHours(),
      date.getMinutes(),
      date.getSeconds(),
      date.getMilliseconds(),
    );
  }

  function unitPositionLabel(periodValue, now, lifetimeStart) {
    const period = normalizePeriod(periodValue);
    if (period === "lifetime") return "1/1";

    if (period === "year") {
      const total = 80;
      const end = addYears(lifetimeStart, total);
      if (now >= end) return formatUnitPosition(total, total);

      let elapsed = now.getFullYear() - lifetimeStart.getFullYear();
      if (now < addYears(lifetimeStart, elapsed)) elapsed -= 1;
      return formatUnitPosition(clamp(elapsed + 1, 1, total), total);
    }

    if (period === "month") {
      const total = 80 * 12;
      const end = addYears(lifetimeStart, 80);
      if (now >= end) return formatUnitPosition(total, total);

      let elapsed =
        (now.getFullYear() - lifetimeStart.getFullYear()) * 12 +
        now.getMonth() -
        lifetimeStart.getMonth();
      if (now < addMonths(lifetimeStart, elapsed)) elapsed -= 1;
      return formatUnitPosition(clamp(elapsed + 1, 1, total), total);
    }

    const unitDuration = unitDurations[period];
    const duration = calendarTime(addYears(lifetimeStart, 80)) - calendarTime(lifetimeStart);
    const elapsed = clamp(calendarTime(now) - calendarTime(lifetimeStart), 0, duration);
    const total = Math.ceil(duration / unitDuration);
    const current = elapsed >= duration ? total : Math.floor(elapsed / unitDuration) + 1;
    return formatUnitPosition(clamp(current, 1, total), total);
  }

  return { range, progress, unitPositionLabel };
});
