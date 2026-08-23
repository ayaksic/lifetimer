(function (root) {
  "use strict";

  const schemaVersion = 1;
  const defaultLifetimeStartISO = "1985-04-17T08:41:00.000Z";
  const cacheKeyPrefix = "lifeTimer.settings.web.v1";
  const legacyLifetimeStartKey = "lifeTimerLifetimeStart";
  const legacyUnitPositionKey = "lifeTimerUnitPositionEnabled";
  const legacyUpdatedAtKey = "lifeTimerSettingsUpdatedAt";

  function normalizedIdentity(accountIdentity) {
    if (typeof accountIdentity !== "string") return null;
    const value = accountIdentity.trim();
    return value.length > 0 ? value : null;
  }

  function cacheKey(accountIdentity) {
    const identity = normalizedIdentity(accountIdentity);
    return identity
      ? `${cacheKeyPrefix}.account.${encodeURIComponent(identity)}`
      : `${cacheKeyPrefix}.anonymous`;
  }

  function validDate(value) {
    const date = value instanceof Date ? value : new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function defaultSettings() {
    return {
      schemaVersion,
      lifetimeStart: new Date(defaultLifetimeStartISO),
      unitPositionEnabled: false,
      updatedAt: new Date(0),
    };
  }

  function decodedSettings(value) {
    if (!value || typeof value !== "object" || value.schemaVersion !== schemaVersion) {
      return null;
    }
    if (typeof value.unitPositionEnabled !== "boolean") return null;
    const lifetimeStart = validDate(value.lifetimeStart);
    const updatedAt = validDate(value.updatedAt);
    if (!lifetimeStart || !updatedAt) return null;
    return {
      schemaVersion,
      lifetimeStart,
      unitPositionEnabled: value.unitPositionEnabled,
      updatedAt,
    };
  }

  function readCanonical(storage, accountIdentity) {
    try {
      const serialized = storage.getItem(cacheKey(accountIdentity));
      return serialized ? decodedSettings(JSON.parse(serialized)) : null;
    } catch (error) {
      return null;
    }
  }

  function parseLegacyLifetimeStart(value) {
    if (typeof value !== "string") return null;
    const match = value.match(
      /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/,
    );
    if (!match) return null;
    const [, rawYear, rawMonth, rawDay, rawHour, rawMinute] = match;
    const year = Number(rawYear);
    const month = Number(rawMonth) - 1;
    const day = Number(rawDay);
    const hour = Number(rawHour);
    const minute = Number(rawMinute);
    const date = new Date(year, month, day, hour, minute, 0, 0);
    if (
      date.getFullYear() !== year ||
      date.getMonth() !== month ||
      date.getDate() !== day ||
      date.getHours() !== hour ||
      date.getMinutes() !== minute
    ) {
      return null;
    }
    return date;
  }

  function readLegacy(storage) {
    let lifetimeStartValue;
    let unitPositionValue;
    let updatedAtValue;
    try {
      lifetimeStartValue = storage.getItem(legacyLifetimeStartKey);
      unitPositionValue = storage.getItem(legacyUnitPositionKey);
      updatedAtValue = storage.getItem(legacyUpdatedAtKey);
    } catch (error) {
      return null;
    }
    if (
      lifetimeStartValue == null &&
      unitPositionValue == null &&
      updatedAtValue == null
    ) {
      return null;
    }

    const fallback = defaultSettings();
    const lifetimeStart = lifetimeStartValue == null
      ? fallback.lifetimeStart
      : parseLegacyLifetimeStart(lifetimeStartValue);
    const unitPositionIsValid = unitPositionValue == null
      || unitPositionValue === "true"
      || unitPositionValue === "false";
    const updatedAt = updatedAtValue == null ? null : validDate(updatedAtValue);
    const legacyPayloadIsValid = lifetimeStart && unitPositionIsValid;

    return {
      schemaVersion,
      lifetimeStart: lifetimeStart || fallback.lifetimeStart,
      unitPositionEnabled: unitPositionValue === "true",
      updatedAt: legacyPayloadIsValid && updatedAt ? updatedAt : new Date(0),
    };
  }

  function save(storage, accountIdentity, settings) {
    const value = decodedSettings(settings);
    if (!value) throw new TypeError("Life Timer settings must match schema version 1");
    const serialized = JSON.stringify({
      schemaVersion,
      lifetimeStart: value.lifetimeStart.toISOString(),
      unitPositionEnabled: value.unitPositionEnabled,
      updatedAt: value.updatedAt.toISOString(),
    });
    try {
      storage.setItem(cacheKey(accountIdentity), serialized);
      return true;
    } catch (error) {
      return false;
    }
  }

  function load(storage, accountIdentity) {
    const canonical = readCanonical(storage, accountIdentity);
    if (canonical) return canonical;

    if (normalizedIdentity(accountIdentity)) return defaultSettings();
    const legacy = readLegacy(storage);
    if (!legacy) return defaultSettings();
    save(storage, null, legacy);
    return legacy;
  }

  root.LifeTimerWebSettingsStorage = {
    cacheKey,
    defaultLifetimeStart() {
      return new Date(defaultLifetimeStartISO);
    },
    load,
    save,
  };
})(window);
