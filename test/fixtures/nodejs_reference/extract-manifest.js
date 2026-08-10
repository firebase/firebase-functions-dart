/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Script to extract the functions manifest from the Node.js SDK.
 * This mimics what firebase-tools does when discovering functions,
 * and produces a JSON manifest compatible with the Dart builder output.
 *
 * Usage: node extract-manifest.js
 * Output: nodejs_manifest.json
 */

const fs = require("fs");
const path = require("path");

// Load the functions module (this registers params and defines exports)
const functionsModule = require("./index.js");

// Access the internal params registry
const params = require("firebase-functions/params");

// =============================================================================
// Param extraction
// =============================================================================

/**
 * Extract declared params from the firebase-functions internal registry.
 * After index.js is loaded, all defineString/defineInt/defineBoolean calls
 * have registered their params globally.
 */
function extractParams() {
  const declaredParams = params.declaredParams;
  if (!Array.isArray(declaredParams) || declaredParams.length === 0) {
    return [];
  }

  return declaredParams.map((p) => {
    const typeMap = {
      StringParam: "string",
      IntParam: "int",
      BooleanParam: "boolean",
      FloatParam: "float",
      ListParam: "list",
      SecretParam: "secret",
    };

    const result = { name: p.name };

    const paramType = typeMap[p.constructor.name];
    if (paramType) result.type = paramType;

    // Copy options (default, label, description)
    if (p.options) {
      if (p.options.default !== undefined) result.default = p.options.default;
      if (p.options.label) result.label = p.options.label;
      if (p.options.description) result.description = p.options.description;
    }

    return result;
  });
}

// =============================================================================
// Endpoint extraction
// =============================================================================

/**
 * Extract __endpoint metadata from all exported functions.
 */
function extractEndpoints(mod) {
  const endpoints = {};

  for (const [key, value] of Object.entries(mod)) {
    if (typeof value === "function" && value.__endpoint) {
      endpoints[key] = normalizeEndpoint(key, value.__endpoint);
    }
  }

  return endpoints;
}

/**
 * Normalize an endpoint to match the format expected by snapshot tests.
 * - Strips null/undefined values
 * - Adds default region if missing
 * - Strips false values from blocking trigger options
 * - Handles CEL expressions from params
 */
function normalizeEndpoint(name, endpoint) {
  const result = { entryPoint: name };

  // Platform
  result.platform = endpoint.platform || "gcfv2";

  // Region (default to us-central1 if not specified)
  const region = wireValue(endpoint.region);
  if (region && Array.isArray(region) && region.length > 0) {
    result.region = region;
  } else {
    result.region = ["us-central1"];
  }

  // Global options - only include non-null values
  copyIfNonNull(result, endpoint, "availableMemoryMb");
  copyIfNonNull(result, endpoint, "timeoutSeconds");
  copyIfNonNull(result, endpoint, "minInstances");
  copyIfNonNull(result, endpoint, "maxInstances");
  copyIfNonNull(result, endpoint, "concurrency");
  copyIfNonNull(result, endpoint, "serviceAccountEmail");
  copyIfNonNull(result, endpoint, "ingressSettings");
  copyIfNonNull(result, endpoint, "cpu");

  // Omit flag
  if (endpoint.omit === true || endpoint.omit === false) {
    result.omit = endpoint.omit;
  }

  // Labels (include even if empty)
  if (endpoint.labels && Object.keys(endpoint.labels).length > 0) {
    result.labels = endpoint.labels;
  }

  // VPC
  if (endpoint.vpc && typeof endpoint.vpc === "object") {
    const vpc = {};
    if (endpoint.vpc.connector) vpc.connector = endpoint.vpc.connector;
    if (endpoint.vpc.egressSettings) vpc.egressSettings = endpoint.vpc.egressSettings;
    if (Object.keys(vpc).length > 0) {
      result.vpc = vpc;
    }
  }

  // Secrets — normalize to {key, secret} pairs to match Dart manifest format
  if (Array.isArray(endpoint.secretEnvironmentVariables) && endpoint.secretEnvironmentVariables.length > 0) {
    result.secretEnvironmentVariables = endpoint.secretEnvironmentVariables.map((s) => ({
      key: s.key,
      secret: s.secret ?? s.key,
    }));
  }

  // Trigger types
  if (endpoint.callableTrigger !== undefined) {
    result.callableTrigger = endpoint.callableTrigger || {};
  } else if (endpoint.httpsTrigger !== undefined) {
    result.httpsTrigger = normalizeHttpsTrigger(endpoint.httpsTrigger);
  } else if (endpoint.eventTrigger) {
    result.eventTrigger = normalizeEventTrigger(endpoint.eventTrigger);
  } else if (endpoint.blockingTrigger) {
    result.blockingTrigger = normalizeBlockingTrigger(endpoint.blockingTrigger);
  } else if (endpoint.scheduleTrigger) {
    result.scheduleTrigger = normalizeScheduleTrigger(endpoint.scheduleTrigger);
  } else if (endpoint.taskQueueTrigger !== undefined) {
    result.taskQueueTrigger = normalizeTaskQueueTrigger(endpoint.taskQueueTrigger);
  }

  return result;
}

function normalizeHttpsTrigger(trigger) {
  if (!trigger || typeof trigger !== "object") return {};
  const result = {};
  if (trigger.invoker && Array.isArray(trigger.invoker) && trigger.invoker.length > 0) {
    result.invoker = trigger.invoker;
  }
  return result;
}

function normalizeEventTrigger(trigger) {
  const result = {};
  if (trigger.eventType) result.eventType = trigger.eventType;

  if (trigger.eventFilters) {
    result.eventFilters = trigger.eventFilters;
  }
  if (trigger.eventFilterPathPatterns) {
    result.eventFilterPathPatterns = trigger.eventFilterPathPatterns;
  }

  result.retry = trigger.retry === true ? true : false;

  // Include channel for Eventarc triggers
  if (trigger.channel) {
    result.channel = trigger.channel;
  }

  return result;
}

function normalizeBlockingTrigger(trigger) {
  const result = {};
  if (trigger.eventType) result.eventType = trigger.eventType;

  // Strip false values from options (Dart builder only includes true values)
  const options = {};
  if (trigger.options) {
    for (const [key, value] of Object.entries(trigger.options)) {
      if (value === true) {
        options[key] = true;
      }
    }
  }
  result.options = options;

  return result;
}

function normalizeScheduleTrigger(trigger) {
  const result = {};
  if (trigger.schedule) result.schedule = trigger.schedule;

  // timeZone may be a ResetValue (for basic schedules)
  const tz = wireValue(trigger.timeZone);
  if (tz) result.timeZone = tz;

  // Include retryConfig only if it has non-null/non-ResetValue values
  if (trigger.retryConfig && typeof trigger.retryConfig === "object") {
    const rc = {};
    for (const [key, value] of Object.entries(trigger.retryConfig)) {
      const wired = wireValue(value);
      if (wired !== undefined && wired !== null) {
        rc[key] = wired;
      }
    }
    if (Object.keys(rc).length > 0) {
      result.retryConfig = rc;
    }
  }

  return result;
}

function normalizeTaskQueueTrigger(trigger) {
  const result = {};

  // Include retryConfig only with non-null/non-ResetValue values
  if (trigger.retryConfig && typeof trigger.retryConfig === "object") {
    const rc = {};
    for (const [key, value] of Object.entries(trigger.retryConfig)) {
      const wired = wireValue(value);
      if (wired !== undefined && wired !== null) {
        rc[key] = wired;
      }
    }
    result.retryConfig = rc;
  } else {
    result.retryConfig = {};
  }

  // Include rateLimits only with non-null/non-ResetValue values
  if (trigger.rateLimits && typeof trigger.rateLimits === "object") {
    const rl = {};
    for (const [key, value] of Object.entries(trigger.rateLimits)) {
      const wired = wireValue(value);
      if (wired !== undefined && wired !== null) {
        rl[key] = wired;
      }
    }
    result.rateLimits = rl;
  } else {
    result.rateLimits = {};
  }

  return result;
}

/**
 * Copy a value from source to target only if non-null/undefined.
 * Handles CEL Expression objects.
 */
function copyIfNonNull(target, source, key) {
  const value = wireValue(source[key]);
  if (value !== null && value !== undefined) {
    target[key] = value;
  }
}

/**
 * Convert a value to wire format.
 * Handles Param objects, TernaryExpression (CEL), and ResetValues.
 *
 * The firebase-functions SDK uses:
 * - IntParam/StringParam/BooleanParam: toString() => "params.NAME"
 * - TernaryExpression: toString() => "params.NAME ? trueVal : falseVal"
 * - ResetValue: indicates a default/unset value (treat as null)
 */
function wireValue(value) {
  if (value === null || value === undefined) {
    return value;
  }

  // Handle non-array objects (possible SDK types)
  if (value && typeof value === "object" && !Array.isArray(value)) {
    // Handle ResetValue (indicates default/unset)
    if (value.constructor?.name === "ResetValue") {
      return null;
    }

    // Handle Param references and expressions via toString()
    // SDK types like IntParam, TernaryExpression have toString() returning "params.XXX"
    const str = value.toString();
    if (str && str.startsWith("params.")) {
      return `{{ ${str} }}`;
    }
  }

  // Handle arrays
  if (Array.isArray(value)) {
    return value.map(wireValue);
  }

  return value;
}

// =============================================================================
// RequiredAPIs extraction
// =============================================================================

/**
 * Collect requiredAPIs from all function __requiredAPIs metadata.
 * Always includes cloudfunctions.googleapis.com.
 */
function extractRequiredAPIs(mod) {
  const apiMap = new Map();

  // Always include Cloud Functions API
  apiMap.set("cloudfunctions.googleapis.com", "Required for Cloud Functions");

  // Collect from each function's __requiredAPIs
  for (const [, value] of Object.entries(mod)) {
    if (typeof value === "function" && Array.isArray(value.__requiredAPIs)) {
      for (const api of value.__requiredAPIs) {
        if (api.api && !apiMap.has(api.api)) {
          // Normalize the reason text (remove trailing periods for consistency)
          const reason = (api.reason || "").replace(/\.$/, "");
          apiMap.set(api.api, reason);
        }
      }
    }
  }

  return Array.from(apiMap.entries()).map(([api, reason]) => ({ api, reason }));
}

// =============================================================================
// Main
// =============================================================================

const paramsList = extractParams();
const endpoints = extractEndpoints(functionsModule);
const requiredAPIs = extractRequiredAPIs(functionsModule);

const manifest = {
  specVersion: "v1alpha1",
  params: paramsList.length > 0 ? paramsList : undefined,
  requiredAPIs,
  endpoints,
};

// Write JSON to nodejs_manifest.json
const outputPath = path.join(__dirname, "nodejs_manifest.json");
const json = JSON.stringify(manifest, null, 4) + "\n";
fs.writeFileSync(outputPath, json, "utf8");

console.log(`Manifest written to ${outputPath}`);
console.log(`  Params: ${paramsList.length}`);
console.log(`  RequiredAPIs: ${requiredAPIs.length}`);
console.log(`  Endpoints: ${Object.keys(endpoints).length}`);
