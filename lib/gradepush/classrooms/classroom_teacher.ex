defmodule GradePush.Classrooms.ClassroomTeacher do
  @primary_key false
  use Ecto.Schema

  alias GradePush.Accounts.User
  alias GradePush.Classrooms.Classroom

  schema "classroom_teachers" do
    belongs_to :classroom, Classroom, primary_key: true
    belongs_to :user, User, primary_key: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
