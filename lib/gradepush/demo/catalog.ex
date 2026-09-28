defmodule GradePush.Demo.Catalog do
  @moduledoc false

  def classrooms do
    [
      %{
        slug: "programming",
        title: "Algorithmes et introduction à la programmation",
        code: "420-1J6-SO",
        description:
          "Analyser un problème et construire une solution avec des conditions, des boucles et des fonctions.",
        semester: :fall,
        academic_year: "2026",
        students: 24,
        shared: true,
        assignments: [
          assignment(
            "loops",
            "Boucles et collections",
            ~D[2026-09-18],
            "Développez un programme Java qui calcule des statistiques à partir d’une série de températures.",
            [
              "Lire les températures jusqu’à la valeur d’arrêt.",
              "Afficher le minimum, le maximum et la moyenne.",
              "Traiter une série vide sans provoquer d’erreur."
            ],
            accepted: 7
          ),
          assignment(
            "cli",
            "Analyseur d’arguments CLI",
            ~D[2026-10-02],
            "Créez un outil Java en ligne de commande pour préparer la liste de matériel d’un laboratoire.",
            [
              "Accepter les options --article et --quantite.",
              "Refuser une quantité négative ou une option inconnue.",
              "Afficher l’aide lorsque l’option --help est présente."
            ],
            accepted: 19,
            template_repository: "gradepush-demo/starter",
            tests: cli_tests()
          ),
          assignment(
            "functions",
            "Fonctions et tests",
            ~D[2026-10-16],
            "En binôme, construisez une bibliothèque Java pour convertir des unités de mesure.",
            [
              "Séparer les conversions de température, de distance et de masse.",
              "Ajouter des tests pour les valeurs limites.",
              "Décrire la répartition du travail dans le README."
            ],
            kind: "team",
            team_mode: "teacher",
            accepted: 20,
            tests: java_tests()
          )
        ]
      },
      %{
        slug: "web-development",
        title: "Web I - Langages de présentation",
        code: "420-1U3-SO",
        description:
          "Structurer et mettre en page des sites avec HTML et CSS en soignant leur ergonomie.",
        semester: :fall,
        academic_year: "2026",
        students: 20,
        shared: false,
        assignments: [
          assignment(
            "semantic-html",
            "Une page pour le café étudiant",
            ~D[2026-09-23],
            "Présentez le menu et les heures d’ouverture d’un café étudiant fictif avec une page HTML sémantique.",
            [
              "Organiser la page avec des titres hiérarchisés.",
              "Associer un libellé à chaque champ du formulaire de contact.",
              "Prévoir un texte de remplacement pertinent pour les images."
            ],
            accepted: 18,
            tests: web_tests()
          ),
          assignment(
            "portfolio",
            "Portfolio adaptatif",
            ~D[2026-10-09],
            "Réalisez un portfolio qui présente trois de vos projets et reste agréable à consulter sur téléphone.",
            [
              "Construire les sections présentation, projets et contact.",
              "Utiliser Grid ou Flexbox pour adapter la mise en page.",
              "Vérifier la navigation au clavier et les contrastes."
            ],
            accepted: 15,
            tests: web_tests()
          ),
          assignment(
            "community-site",
            "Site d’un organisme communautaire",
            ~D[2026-11-06],
            "Formez une équipe de trois et concevez le site d’un organisme fictif de votre choix.",
            [
              "Créer trois pages reliées par une navigation commune.",
              "Partager les styles et vérifier chaque page sur mobile.",
              "Documenter les sources des images et la contribution de chaque membre."
            ],
            kind: "team",
            team_mode: "students",
            team_size: 3,
            accepted: 12
          )
        ]
      },
      %{
        slug: "procedural-programming",
        title: "Paradigme de programmation procédurale",
        code: "420-2J6-SO",
        description:
          "Organiser des programmes en C avec des fonctions, des structures et des fichiers.",
        semester: :winter,
        academic_year: "2026",
        students: 18,
        shared: true,
        assignments: [
          assignment(
            "conversions",
            "Convertisseur d’unités",
            ~D[2026-02-13],
            "Programmez un menu de conversion de distances et de températures en C.",
            [
              "Valider chaque valeur saisie.",
              "Isoler chaque conversion dans une fonction.",
              "Compiler sans avertissement avec -Wall -Wextra."
            ],
            accepted: 18
          ),
          assignment(
            "inventory",
            "Inventaire du laboratoire",
            ~D[2026-03-20],
            "Gérez le matériel d’un laboratoire avec des structures et un fichier CSV.",
            [
              "Ajouter, rechercher et modifier un article.",
              "Sauvegarder puis recharger l’inventaire.",
              "Tester les fichiers absents ou mal formés."
            ],
            accepted: 18,
            tests: c_tests()
          ),
          assignment(
            "reservations",
            "Gestionnaire de réservations",
            ~D[2026-05-08],
            "En binôme, réalisez un outil de réservation de postes de travail.",
            [
              "Détecter les conflits de réservation.",
              "Répartir le code en modules avec des fichiers d’en-tête.",
              "Fournir un jeu de données et une démonstration reproductible."
            ],
            kind: "team",
            team_mode: "teacher",
            accepted: 18
          )
        ]
      },
      %{
        slug: "databases",
        title: "Base de données I - Exploitation",
        code: "420-2R3-SO",
        description:
          "Interroger et modifier des données relationnelles avec SQL, des filtres et des jointures.",
        semester: :winter,
        academic_year: "2026",
        students: 22,
        shared: false,
        assignments: [
          assignment(
            "catalog",
            "Catalogue de la bibliothèque",
            ~D[2026-02-20],
            "Écrivez des requêtes SQL pour explorer un catalogue de livres et leurs emprunts.",
            [
              "Filtrer les ouvrages par auteur et par année.",
              "Relier les livres, les membres et les emprunts.",
              "Classer les résultats avec un ordre déterministe."
            ],
            accepted: 22
          ),
          assignment(
            "reports",
            "Rapports de fréquentation",
            ~D[2026-03-27],
            "Préparez les requêtes nécessaires au bilan mensuel d’une bibliothèque fictive.",
            [
              "Calculer les emprunts par catégorie.",
              "Inclure les membres sans emprunt.",
              "Expliquer les jointures et les regroupements utilisés."
            ],
            accepted: 20
          ),
          assignment(
            "transactions",
            "Emprunts et transactions",
            ~D[2026-05-01],
            "En équipe, sécurisez les opérations d’emprunt et de retour dans une base PostgreSQL.",
            [
              "Protéger les mises à jour avec des transactions.",
              "Vérifier les contraintes d’intégrité.",
              "Fournir les scripts SQL et les résultats attendus."
            ],
            kind: "team",
            team_mode: "students",
            accepted: 20
          )
        ]
      },
      %{
        slug: "workstation",
        title: "Exploitation d’une station de travail",
        code: "420-1X4-SO",
        description:
          "Configurer une station de travail et utiliser les outils du système d’exploitation.",
        semester: :fall,
        academic_year: "2025",
        students: 16,
        shared: false,
        assignments: [
          assignment(
            "terminal",
            "Premiers pas dans le terminal",
            ~D[2025-09-26],
            "Préparez un aide-mémoire des commandes utiles pour gérer les fichiers d’un projet.",
            [
              "Créer et parcourir une arborescence de dossiers.",
              "Rechercher des fichiers et filtrer leur contenu.",
              "Présenter des exemples commentés dans le README."
            ],
            accepted: 16
          ),
          assignment(
            "backup",
            "Sauvegarde automatisée",
            ~D[2025-10-24],
            "Écrivez un script Bash qui archive un dossier de travail sans écraser les sauvegardes précédentes.",
            [
              "Vérifier que le dossier source existe.",
              "Nommer l’archive avec une date.",
              "Tester la restauration dans un dossier temporaire."
            ],
            accepted: 15,
            tests: backup_tests()
          ),
          assignment(
            "workstation-guide",
            "Guide d’installation du poste",
            ~D[2025-12-05],
            "En binôme, documentez l’installation d’un environnement de développement reproductible.",
            [
              "Lister les outils et les versions utilisés.",
              "Expliquer la configuration de Git et de l’éditeur.",
              "Faire suivre le guide par votre partenaire sur un poste vierge."
            ],
            kind: "team",
            team_mode: "teacher",
            accepted: 16
          )
        ]
      },
      %{
        slug: "it-professions",
        title: "Introduction aux professions de TI",
        code: "420-1T4-SO",
        description:
          "Découvrir les métiers de l’informatique et les pratiques de collaboration professionnelle.",
        semester: :fall,
        academic_year: "2025",
        students: 20,
        shared: true,
        assignments: [
          assignment(
            "career",
            "Portrait d’un métier en TI",
            ~D[2025-10-03],
            "Présentez un métier de l’informatique à partir de deux offres d’emploi publiques.",
            [
              "Distinguer les responsabilités et les compétences recherchées.",
              "Citer les sources consultées.",
              "Présenter votre synthèse dans un document Markdown."
            ],
            accepted: 20
          ),
          assignment(
            "collaboration",
            "Collaborer avec Git",
            ~D[2025-11-14],
            "Créez en équipe un petit guide des pratiques de collaboration sur GitHub.",
            [
              "Utiliser une branche par contribution.",
              "Relire la contribution d’un collègue dans une pull request.",
              "Résoudre ensemble un conflit simple et documenter la démarche."
            ],
            kind: "team",
            team_mode: "students",
            team_size: 3,
            accepted: 18
          ),
          assignment(
            "journal",
            "Journal de découverte",
            nil,
            "Conservez vos observations sur les outils et les métiers explorés pendant la session.",
            [
              "Ajouter une courte entrée après chaque atelier.",
              "Relier chaque observation à une compétence professionnelle.",
              "Terminer avec vos objectifs personnels pour la prochaine session."
            ],
            accepted: 17
          )
        ]
      }
    ]
  end

  defp assignment(slug, title, deadline, objective, requirements, options) do
    instructions = """
    ## Objectif

    #{objective}

    ## À réaliser

    #{Enum.map_join(requirements, "\n", &"- #{&1}")}

    ## Remise

    Poussez votre travail sur la branche `main` du dépôt du devoir. Ajoutez au README les étapes nécessaires pour le consulter ou l’exécuter.
    """

    Map.merge(
      %{slug: slug, title: title, deadline: deadline, instructions: instructions, tests: []},
      Map.new(options)
    )
  end

  defp cli_tests do
    [
      %{
        name: "Compilation",
        description: "Le programme Java compile sans erreur.",
        type: "command",
        points: 20,
        command: "javac Main.java"
      },
      %{
        name: "Affichage de l’aide",
        description: "L’option --help affiche le format des arguments attendus.",
        type: "io",
        points: 30,
        command: "java Main.java --help",
        expected: "Usage: java Main.java --article NOM --quantite N"
      },
      %{
        name: "Fichier principal",
        description: "Le point d’entrée Main.java est présent à la racine.",
        type: "file",
        points: 50,
        path: "Main.java"
      }
    ]
  end

  defp java_tests do
    [
      %{
        name: "Tests des conversions",
        description: "Les conversions respectent les valeurs attendues et les cas limites.",
        type: "command",
        points: 70,
        command: "./mvnw test"
      },
      %{
        name: "Documentation",
        description: "Le dépôt contient un README.md pour documenter le projet.",
        type: "file",
        points: 30,
        path: "README.md"
      }
    ]
  end

  defp web_tests do
    [
      %{
        name: "Page principale",
        description: "Le site possède une page d’accueil index.html.",
        type: "file",
        points: 20,
        path: "index.html"
      },
      %{
        name: "Feuille de styles",
        description: "Les styles sont regroupés dans styles.css.",
        type: "file",
        points: 30,
        path: "styles.css"
      },
      %{
        name: "Langue du document",
        description: "L’élément html déclare la langue française.",
        type: "command",
        points: 50,
        command: "grep -Eq '<html[^>]*lang=\"fr\"' index.html"
      }
    ]
  end

  defp c_tests do
    [
      %{
        name: "Compilation stricte",
        description: "Le projet compile sans avertissement.",
        type: "command",
        points: 20,
        command: "make CFLAGS='-Wall -Wextra -Werror'"
      },
      %{
        name: "Tests de l’inventaire",
        description: "Les opérations d’inventaire passent les tests du projet.",
        type: "command",
        points: 30,
        command: "make test"
      },
      %{
        name: "Fichier de construction",
        description: "Le dépôt contient un Makefile.",
        type: "file",
        points: 50,
        path: "Makefile"
      }
    ]
  end

  defp backup_tests do
    [
      %{
        name: "Script de sauvegarde",
        description: "Le script backup.sh est présent.",
        type: "file",
        points: 20,
        path: "backup.sh"
      },
      %{
        name: "Syntaxe Bash",
        description: "Le script ne contient pas d’erreur de syntaxe.",
        type: "command",
        points: 30,
        command: "bash -n backup.sh"
      },
      %{
        name: "Instructions de restauration",
        description: "Un guide de restauration accompagne le script.",
        type: "file",
        points: 50,
        path: "README.md"
      }
    ]
  end
end
