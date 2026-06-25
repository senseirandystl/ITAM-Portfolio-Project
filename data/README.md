# Data Folder – Bulk Loading Examples

This folder contains sample CSV files that can be loaded using PostgreSQL's `\COPY` command for fast bulk inserts (much faster than individual INSERT statements for large datasets).

## How to Load

```bash
psql -h localhost -U postgres -d itam_db

\copy departments FROM 'data/departments.csv' WITH (FORMAT csv, HEADER true);
\copy employees FROM 'data/employees.csv' WITH (FORMAT csv, HEADER true);
```
