<?php
  require('/usr/local/opencastconfig/timetableauth.php');
  //Allow cross domain requests from anywhere (constrain origin afterwards?)
  header("Access-Control-Allow-Origin: " . ORIGIN);
  header("Access-Control-Allow-Methods: GET, POST, OPTIONS");         
  header('Access-Control-Allow-Headers: Origin, Content-Type, X-Auth-Token , Authorization');

  if (!isset($_GET['course'])) {
    include('description.html');
    exit();
  }

  $courseArr = explode(',', $_GET['course']);
  if (sizeof($courseArr) !== 2 || !is_numeric($courseArr[1])) {
    header('HTTP/1.1 400 Please provide a numeric term');
    include('description.html');
    exit();
  }
  if (isset($_GET['event-date'])) {
    $evDate = $_GET['event-date'];
  }
  if (isset($_GET['start'])) {
    $start = $_GET['start'];
  }
  if (isset($_GET['end'])) {
    $end = $_GET['end'];
  }
  if (isset($_GET['venue'])) {
    $venue = $_GET['venue'];
  }


  $db = new PDO('mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8', DB_USER, DB_PASS);

  header('Content-Type: application/json');
  
  // Query from timetable workflow operation
  if (isset($evDate) && isset($start) && isset($end) && isset($venue)) {
    $weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    $day = date('D', strtotime("$evDate $start"));
    $weekPattern = '';
    for ($i = 0; $i < 7; $i++) {
      $weekPattern .= $weekdays[$i] === $day ? 'Y' : '_';
    }
    
    $qry = "select * from sn_timetable inner join opencast_venues on sn_timetable.venue = opencast_venues.sn_venue where course_code = :course and weekdays like :pattern and start_date <= :date and end_date >= :date and start_time <= :start_time and end_time >= :start_time and start_time <= :end_time and end_time >= :end_time and ca_name = :venue";
    $bind = [
      ':course' => strtoupper($courseArr[0]),
      ':pattern' => "%$weekPattern%",
      ':date' => $evDate,
      ':start_time' => $start,
      ':end_time' => $end,
      ':venue' => $venue
    ];
    $stmt = $db->prepare($qry);
    $stmt->execute($bind);
    if ($stmt->rowCount() === 0) {
      echo "false";
      exit();
    }
    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo "true";
    exit();
  }


  $qry = "select A.start_date, date_add(A.end_date, interval 1 day) as end_date, A.start_time, A.end_time, A.venue as sn_venue, B.venue_name, B.ca_name, A.course_code, A.class_section, A.class_mtg_nbr, A.instruction_type, A.weekdays, if(curdate() <  date_add(A.end_date, interval 1 day), TRUE, FALSE) as schedulable from sn_timetable A left join opencast_venues B on A.venue = B.sn_venue where A.course_code = :course and A.start_date > :start_date and A.end_date < :end_date and A.venue is not null and A.venue != ''";
  $bind = [
    ':course' => strtoupper($courseArr[0]),
    ':start_date' => $courseArr[1] . '-01-01',
    ':end_date' => ((int) $courseArr[1] + 1) . '-01-01'
  ];
  $stmt = $db->prepare($qry);
  $stmt->execute($bind);
  if ($stmt->rowCount() === 0) {
    echo "{}";
    exit();
  }

  $results = $stmt->fetchAll(PDO::FETCH_ASSOC);
  $response = [
    'course' => $courseArr[0],
    'term' => sizeof($courseArr) === 2 ? $courseArr[1] : date('Y'),
    'start_date' => $results[0]['start_date'],
    'end_date' => $results[0]['end_date'],
  ];

  $instr_types = [];
  $days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  foreach ($results as $result) {
    if (!isset($instr_types[$result['instruction_type']])) {
      $instr_types[$result['instruction_type']] = [];
    }
    $resultDays = [];
    $givenDays = str_split($result['weekdays']);
    foreach ($givenDays as $i => $day) {
      $resultDays[$days[$i]] = ($day === 'Y' ? true : false);
    }
    $instr_types[$result['instruction_type']][] = [
      'start_date' => $result['start_date'],
      'end_date' => $result['end_date'],
      'start_time' => sizeof(explode(':', $result['start_time'])) > 2 ? substr($result['start_time'], 0, strpos($result['start_time'], ':', 4)) : $result['start_time'],
      'end_time' => sizeof(explode(':', $result['end_time'])) > 2 ? substr($result['end_time'], 0, strpos($result['end_time'], ':', 4)) : $result['end_time'],
      'venue' => $result['venue_name'],
      'ca_name' => $result['ca_name'],
      'sn_venue' => $result['sn_venue'],
      'class_section' => $result['class_section'],
      'mtg_nbr' => $result['class_mtg_nbr'],
      'days' => $resultDays,
    ];
    $response['start_date'] = (strtotime($result['start_date']) < strtotime($response['start_date']) ? $result['start_date'] : $response['start_date']);
    $response['end_date'] = (strtotime($result['end_date']) > strtotime($response['end_date']) ? $result['end_date'] : $response['end_date']);
  }
  if (isset($instr_types['LEC'])) {
    $response['LEC'] = $instr_types['LEC'];
  }
  foreach ($instr_types as $type => $vals) {
    if ($type !== 'LEC') {
      $response[$type] = $vals;
    }
  }
  echo json_encode($response);
?>
