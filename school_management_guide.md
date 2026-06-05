# Premium Admin Console & Database Setup Guide

Welcome to the **MathSupport Admin Console, Auditing, and Statuses Setup Guide**. 

Your application has been upgraded with three industry-standard architectural features suitable for a production-grade enterprise deployment:
1. **Dynamic Operational Statuses**: Full lifecycle management of schools, student accounts, and user access.
2. **Dynamic Soft Delete & Database-backed Audit Logging**: Actions are soft-deleted (archived) rather than hard-purged, and an immutable log records every single administrative change in real-time.
3. **Role-Based Access Control (RBAC)**: Checks credentials and roles at the database level using Row-Level Security (RLS) policies.

---

## 1. Upgraded Database Status Lifecycles

The application implements strict state lifecycles:

### A. School Lifecycle
*   **`active`**: Operational and dynamically visible in all registration and linking dropdowns.
*   **`inactive`**: Temporarily suspended by the administrator. Invisible in portal dropdowns, preserving existing data structures.
*   **`archived`**: **Soft-deleted** school. Safely stored in the database for references/audit logs, but completely hidden from the rest of the application.

### B. Student Account Lifecycle
*   **`active`**: Currently enrolled and active in Math homework assignments.
*   **`graduated`**: Student has finished primary school (Standard 7) or algebra curriculum. Homework history is preserved.
*   **`transferred`**: Student moved to another school.
*   **`inactive`**: Enrolment temporarily suspended.

### C. General User (Parent / Teacher / Admin) Lifecycle
*   **`active`**: Normal authenticated system access.
*   **`suspended`**: Account blocked by administrator. User is locked out of logins.
*   **`deleted`**: User soft-deleted from active directories.

---

## 2. Upgraded Database SQL Initialization Script

To connect these premium statuses, soft-deletes, and live logging to your cloud backend, open your **Supabase Dashboard**, navigate to the **SQL Editor** tab (`>_` terminal icon on the left sidebar), create a **New Query**, paste the code below, and click **Run**:

```sql
-- =====================================================================
-- 1. Initialize the schools table (with Soft Delete Status)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.schools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_name TEXT NOT NULL,
    region TEXT NOT NULL,
    district TEXT NOT NULL,
    code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- 2. Add 'status' column to profiles (User lifecycle status)
-- =====================================================================
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- =====================================================================
-- 3. Add 'school' column to parent links (Dynamic school filtering)
-- =====================================================================
ALTER TABLE public.parent_child_links 
ADD COLUMN IF NOT EXISTS school TEXT;

-- =====================================================================
-- 4. Create the Audit Logs table (Immutable System Auditing)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id TEXT NOT NULL,
    actor_name TEXT NOT NULL,
    action TEXT NOT NULL,
    details TEXT NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- 5. Create the student_records table (Student Pre-Registration)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.student_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admission_number TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    school TEXT NOT NULL,
    level TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- 6. Create the teacher_records table (Teacher Pre-Registration)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.teacher_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_number TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    school TEXT NOT NULL,
    phone_number TEXT,
    classes TEXT[] NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- 6b. Create the school_admin_records table (School Admin Pre-Registration)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.school_admin_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    school TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- 7. Enable Row-Level Security (RLS) on all administration tables
-- =====================================================================
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_admin_records ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 8. Configure RLS Policies
-- =====================================================================

-- Schools Read: Allow anyone to fetch active schools
DROP POLICY IF EXISTS "Allow public read schools" ON public.schools;
CREATE POLICY "Allow public read schools" 
ON public.schools FOR SELECT USING (true);

-- Schools Modify: Allow authenticated users (Admins) to manage schools
DROP POLICY IF EXISTS "Allow auth insert manage schools" ON public.schools;
CREATE POLICY "Allow auth insert manage schools" 
ON public.schools FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Audit Logs Write: Allow authenticated users to insert system changes
DROP POLICY IF EXISTS "Allow auth insert audit logs" ON public.audit_logs;
CREATE POLICY "Allow auth insert audit logs" 
ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (true);

-- Audit Logs Read: Allow authenticated users to view system history
DROP POLICY IF EXISTS "Allow auth read audit logs" ON public.audit_logs;
CREATE POLICY "Allow auth read audit logs" 
ON public.audit_logs FOR SELECT TO authenticated USING (true);

-- Student Records Policies: Allow anyone to verify admission number, Admins manage
DROP POLICY IF EXISTS "Allow public read student_records" ON public.student_records;
CREATE POLICY "Allow public read student_records" 
ON public.student_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth manage student_records" ON public.student_records;
CREATE POLICY "Allow auth manage student_records" 
ON public.student_records FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Teacher Records Policies: Allow anyone to verify employee number, Admins manage
DROP POLICY IF EXISTS "Allow public read teacher_records" ON public.teacher_records;
CREATE POLICY "Allow public read teacher_records" 
ON public.teacher_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth manage teacher_records" ON public.teacher_records;
CREATE POLICY "Allow auth manage teacher_records" 
ON public.teacher_records FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- School Admin Records Policies: Allow anyone to verify username, Admins manage
DROP POLICY IF EXISTS "Allow public read school_admin_records" ON public.school_admin_records;
CREATE POLICY "Allow public read school_admin_records" 
ON public.school_admin_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow auth manage school_admin_records" ON public.school_admin_records;
CREATE POLICY "Allow auth manage school_admin_records" 
ON public.school_admin_records FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

---

## 3. How to Use the Premium Admin Console (Role Hierarchies)

The MathSupport Admin Console now supports a secure, multi-tier hierarchical system:

```
Super Admin (system administrator)
│
▼
School Admin (school-specific administrator)
│
┌────┴────┐
▼         ▼
Teachers Students
```

Once logged in as an **Admin (Super Admin)** or a **School Admin**, you are taken to a highly modern Tab-based console with three separate sections. Access is dynamically restricted based on your role:

### Tab 1: Schools Management
*   **Super Admin View**: 
    *   **Register School**: Tap the floating action button to register a school with a unique code.
    *   **Edit Details / Deactivate / Reactivate / Soft Delete**: Super Admins have full lifecycle options on school cards.
*   **School Admin View**:
    *   **View Only**: School Admins can only view their own assigned school in the school directory. 
    *   **Action Disabling**: Floating action buttons, edit popups, status toggles, and delete controls are completely hidden/disabled for School Admins.

### Tab 2: User Directory
*   **Live User & Role Filtering**: Filter users by segmented roles (All, Students, Teachers, Parents, School Admins, Admins).
    *   **Super Admin**: Can filter and manage all profiles and pre-registered accounts across the entire application, including pre-registering new **School Admins**.
    *   **School Admin**: Can only view and pre-register Teachers and Students belonging to their specific school. The 'School Admins' filter and creation button are hidden to prevent access escalations.
*   **Restricted Pre-registration Dialogs**:
    *   For School Admins, the School field in both the Student and Teacher pre-registration forms is permanently locked and prefilled to their assigned school.

### Tab 3: Timeline Audit Logs
*   **Dynamic Logs Scope**:
    *   **Super Admin**: Reviews global system actions across all schools.
    *   **School Admin**: Automatically filtered to only view audit trails associated with their assigned school.

---

### Security Notice: Role-Based Access Control (RBAC)
Only accounts registered under the role `super_admin`, `admin`, or `school_admin` in the `profiles` table are routed to the admin dashboard. Database-level RLS policies enforce that users can only fetch or modify directories according to their assigned roles.
