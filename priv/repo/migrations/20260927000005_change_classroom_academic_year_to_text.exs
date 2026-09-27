defmodule GradePush.Repo.Migrations.ChangeClassroomAcademicYearToText do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE classrooms DROP CONSTRAINT classroom_term_check"

    execute """
    ALTER TABLE classrooms
    ALTER COLUMN academic_year TYPE text
    USING academic_year::text
    """

    create constraint(:classrooms, :classroom_term_check,
             check:
               "(semester IS NULL AND academic_year IS NULL) OR (semester IS NOT NULL AND academic_year IS NOT NULL AND semester IN ('winter', 'summer', 'fall') AND char_length(academic_year) BETWEEN 1 AND 20 AND academic_year ~ '[^[:space:]]')"
           )
  end

  def down do
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM classrooms
        WHERE academic_year IS NOT NULL
          AND academic_year !~ '^(19[0-9]{2}|[2-9][0-9]{3})$'
      ) THEN
        RAISE EXCEPTION 'Cannot convert classroom academic year labels back to integers';
      END IF;
    END;
    $$;
    """

    drop constraint(:classrooms, :classroom_term_check)

    execute """
    ALTER TABLE classrooms
    ALTER COLUMN academic_year TYPE integer
    USING academic_year::integer
    """

    create constraint(:classrooms, :classroom_term_check,
             check:
               "(semester IS NULL AND academic_year IS NULL) OR (semester IS NOT NULL AND academic_year IS NOT NULL AND semester IN ('winter', 'summer', 'fall') AND academic_year BETWEEN 1900 AND 9999)"
           )
  end
end
