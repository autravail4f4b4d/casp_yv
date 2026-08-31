# W2 -- controlled-facet context-compatibility gates.
#
# Every case below is a MEASURED live pre-staging-v8 failure or a
# deliberate guard against over-rejecting while fixing one. The unit tests
# exercise the pure predicate; the integration tests prove the gate is
# actually wired into the resolver rather than merely available.

# --- pure predicate --------------------------------------------------------

test_that("a facet the query does not state yields no opinion", {
  # "nurse" / "private hospital" states no ACTION, so nothing is vetoed on
  # action grounds. Absence must never reject.
  expect_false(assistant_compat_conflict("nurse", "NURSING PROFESSIONALS"))
  expect_false(assistant_compat_conflict("janitor", "BUILDING CARETAKERS"))
  expect_false(assistant_compat_conflict("statistician", "STATISTICIANS"))
})

test_that("activity action: growing is incompatible with milling or preparing", {
  q <- c("palay farming", "growing of rice")
  expect_false(assistant_compat_conflict(q, "Growing of rice"))
  expect_true(assistant_compat_conflict(q, "Rice milling"))
  expect_true(assistant_compat_conflict(q, "Preparation of rice for market"))
})

test_that("activity action: related-but-not-exclusive actions do not veto each other", {
  # Construction work happens at a building; manufacturing overlaps
  # processing. These pairs must stay compatible or correct answers break.
  expect_false(assistant_compat_conflict("residential construction",
                                         "Construction of residential buildings"))
  expect_false(assistant_compat_conflict("repair of buildings",
                                         "Construction of residential buildings"))
})

test_that("education level: private high school rejects pre-primary, keeps secondary", {
  q <- c("private high school", "secondary education")
  expect_true(assistant_compat_conflict(q, "Private pre-primary or pre-school education"))
  expect_false(assistant_compat_conflict(
    q, "Private general secondary education for children without special needs"))
})

test_that("ownership: a private query rejects the public half of a deliberate split", {
  q <- c("private high school", "secondary education")
  expect_true(assistant_compat_conflict(
    q, "Public general secondary education for children without special needs"))
  expect_true(assistant_compat_conflict("private hospital", "Public general hospital activities"))
  expect_false(assistant_compat_conflict("private hospital", "Private general hospital activities"))
})

test_that("ownership: government wording agrees with a public label rather than conflicting", {
  expect_false(assistant_compat_conflict(
    c("city government", "public administration local government"),
    "Public administration, local government"))
})

test_that("occupation role: a principal role does not fall through to its support variant", {
  # The measured 5312 case. Compared by similarity, so the
  # teacher/teachers plural difference does not defeat the rule.
  expect_true(assistant_compat_conflict(c("teacher", "teaching"), "TEACHERS' AIDES"))
  expect_false(assistant_compat_conflict(c("teacher", "teaching"),
                                         "SECONDARY EDUCATION TEACHERS"))
})

test_that("occupation role: a query that DOES describe support duties may match support roles", {
  expect_false(assistant_compat_conflict("teacher aide", "TEACHERS' AIDES"))
  expect_false(assistant_compat_conflict("teaching assistant", "TEACHERS' AIDES"))
})

test_that("occupation role: an unrelated support occupation is not vetoed", {
  # No shared content token, so this rule stays out of it -- the ordinary
  # context gate is what handles unrelated candidates.
  expect_false(assistant_compat_conflict("janitor", "HEALTH CARE ASSISTANTS"))
})

test_that("vehicle type: truck rejects bus and vice versa, parent naming both is exempt", {
  expect_true(assistant_compat_conflict(c("truck driver", "driving"), "BUS AND TRAM DRIVERS"))
  expect_false(assistant_compat_conflict(c("truck driver", "driving"),
                                         "HEAVY TRUCK AND LORRY DRIVERS"))
  expect_false(assistant_compat_conflict(c("truck driver", "driving"),
                                         "HEAVY TRUCK AND BUS DRIVERS"))
  expect_true(assistant_compat_conflict(c("bus driver", "driving"),
                                        "HEAVY TRUCK AND LORRY DRIVERS"))
})

test_that("health service is not public administration", {
  expect_true(assistant_compat_conflict(
    c("national government agency", "public administration"),
    "Public general hospital activities"))
})

# --- specialization and coverage discriminators ----------------------------

test_that("an unasked specialization is penalised, an asked-for one is not", {
  q <- c("private high school", "secondary education")
  expect_gt(assistant_compat_specialization_penalty(
    q, "Private technical and vocational secondary education for children"), 0L)
  expect_gt(assistant_compat_specialization_penalty(
    q, "Private general secondary education for children with special needs"), 0L)
  # The plain reading, and the "without special needs" default, score 0.
  expect_identical(assistant_compat_specialization_penalty(
    q, "Private general secondary education for children without special needs"), 0L)

  asked <- c("private vocational high school")
  expect_identical(assistant_compat_specialization_penalty(
    asked, "Private technical and vocational secondary education for children"), 0L)
})

test_that("query coverage separates siblings the user's wording distinguishes", {
  q <- "private general hospital"
  general <- assistant_compat_coverage(q, "Private general hospital activities")
  mental  <- assistant_compat_coverage(q, "Private mental hospital activities")
  expect_gt(general, mental)
})

test_that("query coverage stays silent where the ambiguity is real", {
  # Nothing in "growing paddy rice" chooses among irrigation regimes, so
  # every sibling must score the same and the question must still be asked.
  q <- c("growing paddy rice", "growing of rice")
  scores <- vapply(c("Growing of rice in irrigated lowland",
                     "Growing of rice in rainfed lowland",
                     "Growing of rice in upland"),
                   function(l) assistant_compat_coverage(q, l), integer(1))
  expect_length(unique(scores), 1L)
})

# --- integration: the gate is actually wired into the resolver -------------

test_that("teacher in a private high school resolves to secondary, not aides or preschool", {
  p <- assistant_coding_service("teacher", "private high school")
  expect_identical(p$occupation$selected_code, "2330")
  expect_false(identical(p$occupation$selected_code, "5312"))
  expect_false(identical(p$industry$selected_code, "85102"))
  # v10 (spec 20): secondary context is recognised, but the detailed
  # subclass is NOT guessed while compatible siblings remain. The verified
  # parent is returned with one real-world question.
  expect_identical(p$industry$selected_code, "8531")
  expect_identical(p$clarification$missing_slot, "establishment_activity_detail")
})

test_that("palay farming never resolves to rice milling", {
  p <- assistant_coding_service(NULL, "palay farming", requested_systems = "psic")
  expect_false(identical(p$industry$selected_code, "10611"))
  # Rice-growing aggregate plus the irrigation question (spec 45).
  expect_identical(p$industry$selected_code, "0112")
  expect_identical(p$clarification$missing_slot, "establishment_activity_detail")
})

test_that("corn farming resolves to the current growing-of-corn subclass", {
  p <- assistant_coding_service("corn farmer", "corn farming in their own farm")
  expect_identical(p$occupation$selected_code, "6112")
  expect_identical(p$industry$selected_code, "01130")
  expect_identical(p$industry$status_current, "current")
})

test_that("truck driver selects the truck unit group, bus driver the bus one", {
  expect_identical(
    assistant_coding_service("truck driver", requested_systems = "psoc")$occupation$selected_code,
    "8332")
  expect_identical(
    assistant_coding_service("heavy truck driver", requested_systems = "psoc")$occupation$selected_code,
    "8332")
  expect_identical(
    assistant_coding_service("bus driver", requested_systems = "psoc")$occupation$selected_code,
    "8331")
})

test_that("naming the hospital type still settles without asking", {
  # Guards the regression the ownership veto nearly caused: removing the
  # public rows exposed private mental/maternity siblings, which must be
  # separated by coverage rather than turned into a spurious question.
  p <- assistant_coding_service("nurse", "private general hospital")
  expect_identical(p$occupation$selected_code, "2221")
  expect_identical(p$industry$selected_code, "86121")
})

test_that("a bare private hospital still asks which kind", {
  p <- assistant_coding_service("nurse", "private hospital")
  expect_identical(p$clarification$missing_slot, "establishment_activity_detail")
})

test_that("the compatibility gate never vetoes PSA survey-manual evidence", {
  # Survey guidance is PSA's own published decision and outranks this
  # heuristic. "Food panda BICYCLE driver" -> 9335 must survive even
  # though the label names a bicycle and the query names a delivery app.
  expect_identical(
    assistant_coding_service("food panda bicycle driver",
                             requested_systems = "psoc")$occupation$selected_code,
    "9335")
  expect_identical(
    assistant_coding_service("angkas driver", requested_systems = "psoc")$occupation$selected_code,
    "8323")
})
