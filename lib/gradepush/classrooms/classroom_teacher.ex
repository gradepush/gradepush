defmodule GradePush.Classrooms.ClassroomTeacher do
  @primary_key false
  use Ecto.Schema

  alias GradePush.Accounts.User
  alias GradePush.Classrooms.Classroom

  schema "classroom_teachers" do
    belongs_to :classroom, Classroom
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
