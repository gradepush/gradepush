defmodule GradePushWeb.Preview.Fixtures do
  @moduledoc "Fictional classroom, student and teacher records for the in-memory UI preview."

  def institution, do: "Cégep de Sorel-Tracy"
  def organizations, do: ["cegep-sorel-tracy"]

  def colleagues do
    [
      %{name: "Camille Bergeron", initials: "CB"},
      %{name: "Alex Nguyen", initials: "AN"}
    ]
  end

  def classrooms do
    [
      %{
        slug: "programming",
        title: %{en: "Programming I", fr: "Programmation I"},
        code: "420-110",
        description: %{
          en: "Build a strong foundation in Python and problem solving.",
          fr: "Développer une base solide en Python et en résolution de problèmes."
        },
        semester: "fall",
        academic_year: 2026,
        students: 28,
        assignments: 3,
        organization: "cegep-sorel-tracy",
        teachers: [
          %{name: "Jordan Rioux", initials: "JR", color: "blue"},
          %{name: "Camille Bergeron", initials: "CB", color: "violet"}
        ]
      },
      %{
        slug: "web-development",
        title: %{en: "Web Development", fr: "Développement Web"},
        code: "420-210",
        description: %{
          en: "Create accessible, responsive experiences for the web.",
          fr: "Créer des expériences Web accessibles et adaptées à tous les écrans."
        },
        semester: "fall",
        academic_year: 2026,
        students: 24,
        assignments: 1,
        organization: "cegep-sorel-tracy",
        teachers: [
          %{name: "Jordan Rioux", initials: "JR", color: "blue"},
          %{name: "Camille Bergeron", initials: "CB", color: "violet"}
        ]
      },
      %{
        slug: "data-structures",
        title: %{en: "Data Structures", fr: "Structures de données"},
        code: "420-310",
        description: %{
          en: "Understand how data structures shape efficient programs.",
          fr: "Comprendre le rôle des structures de données dans les programmes efficaces."
        },
        semester: "winter",
        academic_year: 2027,
        students: 18,
        assignments: 1,
        organization: "cegep-sorel-tracy",
        teachers: [
          %{name: "Jordan Rioux", initials: "JR", color: "blue"}
        ]
      }
    ]
  end

  def classroom(slug) do
    Enum.find(classrooms(), &(&1.slug == slug)) || empty_classroom(slug)
  end

  defp empty_classroom("new") do
    %{
      slug: "new",
      title: %{en: "New classroom", fr: "Nouvelle classe"},
      code: "",
      description: %{en: "", fr: ""},
      students: 0,
      assignments: 0,
      organization: "cegep-sorel-tracy",
      teachers: []
    }
  end

  defp empty_classroom(_slug), do: nil

  def assignments do
    [
      %{
        key: "cli",
        title: %{en: "CLI Argument Parser", fr: "Analyseur d’arguments CLI"},
        classroom: "programming",
        status: :open,
        kind: %{en: "Individual", fr: "Individuel"},
        due: %{en: "Sep 30, 11:59 PM", fr: "30 sept., 23 h 59"},
        submitted: 18,
        total: 28,
        repository: "cegep-sorel-tracy/420-110-cli-parser"
      },
      %{
        key: "loops",
        title: %{en: "Loops and Collections", fr: "Boucles et collections"},
        classroom: "programming",
        status: :closed,
        kind: %{en: "Individual", fr: "Individuel"},
        due: %{en: "Sep 18, 11:59 PM", fr: "18 sept., 23 h 59"},
        submitted: 27,
        total: 28,
        repository: "cegep-sorel-tracy/420-110-loops"
      },
      %{
        key: "functions",
        title: %{en: "Functions and Tests", fr: "Fonctions et tests"},
        classroom: "programming",
        status: :draft,
        kind: %{en: "Teams of 2", fr: "Équipes de 2"},
        due: %{en: "Not published", fr: "Non publié"},
        submitted: 0,
        total: 28,
        repository: "cegep-sorel-tracy/420-110-functions"
      },
      %{
        key: "portfolio",
        title: %{en: "Responsive portfolio", fr: "Portfolio adaptatif"},
        classroom: "web-development",
        status: :open,
        kind: %{en: "Individual", fr: "Individuel"},
        due: %{en: "Oct 2, 11:59 PM", fr: "2 oct., 23 h 59"},
        submitted: 9,
        total: 24,
        repository: "cegep-sorel-tracy/420-210-responsive-portfolio"
      },
      %{
        key: "linked-list",
        title: %{
          en: "Linked list implementation",
          fr: "Implémentation d’une liste chaînée"
        },
        classroom: "data-structures",
        status: :open,
        kind: %{en: "Teams of 2", fr: "Équipes de 2"},
        due: %{en: "Oct 6, 11:59 PM", fr: "6 oct., 23 h 59"},
        submitted: 5,
        total: 18,
        repository: "cegep-sorel-tracy/420-310-linked-list"
      }
    ]
  end

  def students do
    [
      %{
        name: "Amélie Fortin",
        initials: "AF",
        handle: "amelie-fortin",
        status: :active
      },
      %{
        name: "Maxime Fortin",
        initials: "MF",
        handle: "max-fortin",
        status: :active
      },
      %{
        name: "Léa Bouchard",
        initials: "LB",
        handle: "lea-bouchard",
        status: :active
      },
      %{
        name: "Camille Roy",
        initials: "CR",
        handle: "camille-roy",
        status: :active
      },
      %{
        name: "Noah Pelletier",
        initials: "NP",
        handle: "noah-pelletier",
        status: :active
      },
      %{
        name: "Thomas Lavoie",
        initials: "TL",
        handle: "thomas-lavoie",
        status: :active
      },
      %{
        name: "Maude Gauthier",
        initials: "MG",
        handle: "maude-gauthier",
        status: :active
      },
      %{
        name: "Émile Tremblay",
        initials: "ÉT",
        handle: "emile-tremblay",
        status: :active
      },
      %{
        name: "Jade Martel",
        initials: "JM",
        handle: "jade-martel",
        status: :active
      },
      %{
        name: "Antoine Morin",
        initials: "AM",
        handle: "antoine-morin",
        status: :active
      },
      %{
        name: "Rosalie Gervais",
        initials: "RG",
        handle: "rosalie-gervais",
        status: :active
      },
      %{
        name: "Félix Beaulieu",
        initials: "FB",
        handle: "felix-beaulieu",
        status: :active
      },
      %{
        name: "Éloïse Caron",
        initials: "ÉC",
        handle: "eloise-caron",
        status: :active
      },
      %{
        name: "Gabriel Girard",
        initials: "GG",
        handle: "gabriel-girard",
        status: :active
      },
      %{
        name: "Sarah Boucher",
        initials: "SB",
        handle: "sarah-boucher",
        status: :active
      },
      %{
        name: "Louis Côté",
        initials: "LC",
        handle: "louis-cote",
        status: :active
      },
      %{
        name: "Clara Pelletier",
        initials: "CP",
        handle: "clara-pelletier",
        status: :active
      },
      %{
        name: "William Gagné",
        initials: "WG",
        handle: "william-gagne",
        status: :active
      },
      %{
        name: "Mia Leduc",
        initials: "ML",
        handle: "mia-leduc",
        status: :active
      },
      %{
        name: "Raphaël Paquette",
        initials: "RP",
        handle: "raphael-paquette",
        status: :active
      },
      %{
        name: "Florence Simard",
        initials: "FS",
        handle: "florence-simard",
        status: :active
      },
      %{
        name: "Olivier Deschamps",
        initials: "OD",
        handle: "olivier-deschamps",
        status: :active
      },
      %{
        name: "Anaïs Lefebvre",
        initials: "AL",
        handle: "anais-lefebvre",
        status: :active
      },
      %{
        name: "Nathan Renaud",
        initials: "NR",
        handle: "nathan-renaud",
        status: :active
      },
      %{
        name: "Alice Dufour",
        initials: "AD",
        handle: "alice-dufour",
        status: :active
      },
      %{
        name: "Simon Ouellet",
        initials: "SO",
        handle: "simon-ouellet",
        status: :active
      },
      %{name: "Ève Roy", initials: "ÈR", handle: "eve-roy", joined: "Sep 16", status: :active},
      %{
        name: "Mathis Lachance",
        initials: "ML",
        handle: "mathis-lachance",
        status: :active
      }
    ]
  end

  def teachers do
    [
      %{
        name: "Jordan Rioux",
        initials: "JR",
        handle: "mrjordash"
      },
      %{
        name: "Camille Bergeron",
        initials: "CB",
        handle: "camille-bergeron"
      }
    ]
  end
end
