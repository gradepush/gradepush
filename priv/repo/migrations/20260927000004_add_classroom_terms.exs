defmodule GradePush.Repo.Migrations.AddClassroomTerms do
  use Ecto.Migration

  def up do
    alter table(:classrooms) do
      add :semester, :string
      add :academic_year, :integer
    end

    execute """
    WITH recognized_sessions AS (
      SELECT
        id,
        regexp_match(
          session,
          '^[[:space:]]*(fall|autumn|automne|winter|hiver|summer|été|ete)[[:space:]]+(19[0-9]{2}|[2-9][0-9]{3})[[:space:]]*$',
          'i'
        ) AS parts
      FROM classrooms
      WHERE session ~* '^[[:space:]]*(fall|autumn|automne|winter|hiver|summer|été|ete)[[:space:]]+(19[0-9]{2}|[2-9][0-9]{3})[[:space:]]*$'
    )
    UPDATE classrooms AS classroom
    SET
      semester = CASE
        WHEN recognized.parts[1] ~* '^(fall|autumn|automne)$' THEN 'fall'
        WHEN recognized.parts[1] ~* '^(winter|hiver)$' THEN 'winter'
        WHEN recognized.parts[1] ~* '^(summer|été|ete)$' THEN 'summer'
      END,
      academic_year = recognized.parts[2]::integer
    FROM recognized_sessions AS recognized
    WHERE classroom.id = recognized.id
    """

    create constraint(:classrooms, :classroom_term_check,
             check:
               "(semester IS NULL AND academic_year IS NULL) OR (semester IS NOT NULL AND academic_year IS NOT NULL AND semester IN ('winter', 'summer', 'fall') AND academic_year BETWEEN 1900 AND 9999)"
           )
  end

  def down do
    execute """
    UPDATE classrooms
    SET session = CASE semester
      WHEN 'winter' THEN 'Winter'
      WHEN 'summer' THEN 'Summer'
      WHEN 'fall' THEN 'Fall'
    END || ' ' || academic_year::text
    WHERE semester IS NOT NULL AND academic_year IS NOT NULL AND session = ''
    """

    drop constraint(:classrooms, :classroom_term_check)

    alter table(:classrooms) do
      remove :semester
      remove :academic_year
    end
  end
end
