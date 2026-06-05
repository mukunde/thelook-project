// Cube runtime config for the Finance semantic layer.
//
// Connection settings (account, user, role, warehouse, database, schema,
// private key) come from environment variables. See .env.example for
// the documented set, and ADR-0011 for the rationale.
//
// This file only configures structural behaviors that env vars cannot
// drive (schema discovery path, custom security context, query rewrite,
// etc.). Today there is nothing custom yet, the defaults are intentional.

module.exports = {
  // Schema files live under model/ (cubes/ and views/ subdirectories).
  // Cube recursively discovers all .yml files under this path.
  schemaPath: 'model',

  // No custom security context, query rewrite, or driver factory yet.
  // Add them here when consumer-specific access patterns surface
  // (e.g., row-level security for multi-tenant Cube users).
};
