// Data Animation Generator, v2
// Written by Michael Schade, (c)2013 
import java.util.*;  
import java.text.SimpleDateFormat;
// station data from http://mvjantzen.com/cabi/cabixmlbuild.php stored in data/cabi.csv
// add White House manually: 38.896494, -77.038947, 31210 
float minLng;  // left
float maxLng;  // right
float minLat;  // bottom
float maxLat;  // top
int swidth;
int sheight;
int secondsPerFrame;  
int tickCount = 0;
int histogramWidth;
String movieTitle;  
PImage bg; 
List<CaBiTrip> validTrips; 
int maxBusiest = 0;
int[][] tripRiders;
int[][] tripRidersCas;
int mostRidersPerStation;
int maxRidersPerRoute = 0;
int displayMethod; 
static final int CHARCOAL = 0;
static final int RIDERTYPE = 1;
static final int BALANCES = 2;
static final int SWEEP = 3;
static final int BIKEPATH = 4;
int rideTypes;
static final int CASUAL_REGISTERED = 0;
static final int WEEKDAY_WEEKEND = 1;
static final int JURISDICTION = 2;
static final int CLUSTER = 3; 
static final int BIKENO = 4; 
static final int TRIPDAY = 5; 
static final int ALL_TYPES = 6; 
float[][] tripControlX;
float[][] tripControlY;
String[][] paths; 
Calendar minDate, maxDate;
Boolean noDatesSet = true;
Boolean lightmap = true;  // map is lightcolored, not dark (font color depends on this)
int[][] balances;
int[] balanceSum;
String dataTitle;
String subTitle;
static final int SECONDSperDAY = 60*60*24;
cabiStation[] cabiStations;
statKey[] statistics;
Boolean showKeyCalculation = false;

public class statKey {
  // defines a category - shown as a bar in the key as well as the corresponding segment in the histogram
  public String label;
  public color fill;
  public color stroke;
  public color opaque;  // same as fill but without any transparency
  public int count;  // the number of riders matching this category currently on display
  public int[] histogram;  // each element is the value of "count" in that point in time
  public statKey(String l, color f, color s) {
    label = l;
    fill = f;
    stroke = s;
    opaque = color(red(f), green(f), blue(f));
    count = 0;
    }
  }

public class BikeDirections {
  // all the information needed to draw a path between two CaBi stations
  public String start;
  public String end;
  public float[] xPoints;
  public float[] yPoints;  
  public float[] completeness;  // 0 to 1, marking portion of path completed  
  public BikeDirections(String p1, String p2, String dirString) {
    start = p1;
    end = p2;  
    // Java's JSON conversion sucks, so just process as a string, ugh
    String[] segments = dirString.replace("[[", "").replace("]]", "").split("\\],\\[");
    //println(segments.length + " segments");
    xPoints = new float[segments.length]; 
    yPoints = new float[segments.length]; 
    completeness = new float[segments.length]; 
    completeness[0] = 0;
    float length = 0.0;
    for (int i = 0; i < segments.length; i++) {
      String[] lonLat = segments[i].split(",");
      xPoints[i] = toX(parseFloat(lonLat[0]));
      yPoints[i] = toY(parseFloat(lonLat[1]));
      //println(lonLat[0] + " !!!");
      if (i > 0) {
        length += sqrt(sq(xPoints[i] - xPoints[i - 1]) + sq(yPoints[i] - yPoints[i - 1]));
        completeness[i] = length; 
        }  
      }
    // change completeness array from running total to percentage of completeness (0 to 1)
    for (int i = 1; i < segments.length - 1; i++) {
      completeness[i] /= length;
      //println(i+"/"+segments.length+": " + completeness[i]);
      }
    completeness[segments.length - 1] = 1;  // avoid rounding errors
    }
  }

public class CaBiBike {
  // a single Capital Bikeshare bike
  public String bikeID;
  int trips;
  public CaBiBike(String ID) {
    bikeID = ID;
    trips = 1;
    }
  }

public class CaBiTrip { 
  // object for each row in the trip-history open data
  public int bikeoutStation;  // an index to the array which have info for each station
  public int bikeinStation;
  public int bikeoutTime; 
  public int bikeinTime;
  public String bikeNo;
  public String memberZip;
  public Boolean acrossMidnight;  // set to true if you want cross-midnight trips to be shown both in the morning and at night
  public Calendar bikeoutDayTime;
  public Calendar bikeinDayTime;
  public Boolean isRegistered; 
  public Boolean isWeekday; 
  public char gender; 
  public BikeDirections bikeDirections;
  public int category;  // the index of the key (and histogram) which it matches, such as cas-v-reg or weekday-v-weekend
  public CaBiTrip(int stationA, int stationB, String timeA, String timeB, String membership, String idNo, String zip, String sex) { 
    bikeoutStation = stationA; 
    bikeinStation = stationB;
    memberZip = zip;
    if (memberZip.length() > 5) {
      memberZip = zip.substring(0, 5);
      }
    if (sex.length() > 1) {
      gender = sex.charAt(0);  // M or F
      }
    else {
      gender = ' ';
      }
    //println("zip: " + memberZip);
    bikeoutTime = secondsPastMidnight(timeA);
    bikeinTime = secondsPastMidnight(timeB);
    bikeNo = idNo;
    if (bikeinTime < bikeoutTime) {
      bikeinTime += SECONDSperDAY;  // bike was returned the next day
      acrossMidnight = true;
      }
    else
      acrossMidnight = false;  
    bikeoutDayTime = stringToCalendar(timeA);
    //println(bikeoutDayTime.get(Calendar.DAY_OF_MONTH) + " >>> " + timeA);
    bikeinDayTime = stringToCalendar(timeB); 
    if (noDatesSet) {
      minDate = (Calendar) bikeoutDayTime.clone();  // God I hate Java
      maxDate = (Calendar) bikeinDayTime.clone();
      noDatesSet = false;
      }
    else {
      if (bikeoutDayTime.before(minDate))
        minDate = (Calendar) bikeoutDayTime.clone();
      if (bikeinDayTime.after(maxDate))
        maxDate = (Calendar) bikeinDayTime.clone();
      }
    String bikeout = cabiStations[bikeoutStation].id;
    String bikein = cabiStations[bikeinStation].id;
    if (bikeoutStation == bikeinStation) {
      bikeDirections = null;
      }
    else {
      int i = 0; 
      List<BikeDirections> directions = cabiStations[bikeoutStation].directions;
      //println("directions.size(): " + directions.size());
      while (i < directions.size() && !(directions.get(i).start.equals(bikeout) && directions.get(i).end.equals(bikein))) {
        i++;
        }
      if (i < directions.size()) {
        bikeDirections = directions.get(i);
        //println("found directions!");
        } 
      else {
        /*
        if (paths[bikeoutStation][bikeinStation].equals("")) {
          if ((stationIsInImage(bikeoutStation) || stationIsInImage(bikeinStation)) && bikeoutStation != bikeinStation) {
            //println(cabiStations[bikeoutStation].id + "," + cabiStations[bikeinStation].id);
            }
          paths[bikeoutStation][bikeinStation] = "x";
          }
          */
        bikeDirections = null;
        println("no directions for " + bikeout + " to " + bikein);
        }
      }
    isRegistered = !(membership.equals("Casual") || membership.equals("24-hour") || membership.equals("3-Day"));
    isWeekday = bikeoutDayTime.get(Calendar.DAY_OF_WEEK) != Calendar.SATURDAY && bikeoutDayTime.get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY;
    if (rideTypes == CASUAL_REGISTERED)    {if (isRegistered) category = 1; else category = 0;}
    else if (rideTypes == WEEKDAY_WEEKEND) {if (isWeekday)    category = 1; else category = 0;}
    else if (rideTypes == JURISDICTION)    {
      if      (cabiStations[bikeoutStation].jurisdiction.equals("DC"))         {category = 0;}
      else if (cabiStations[bikeoutStation].jurisdiction.equals("Arlington"))  {category = 1;}
      else if (cabiStations[bikeoutStation].jurisdiction.equals("Montgomery")) {category = 3;}
      else if (cabiStations[bikeoutStation].jurisdiction.equals("Alexandria")) {category = 2;}
      else if (cabiStations[bikeoutStation].jurisdiction.equals("Fairfax"))    {category = 4;}
      else {println("Don't recognize jurisdiction " + cabiStations[bikeoutStation].jurisdiction);}
      }
    else if (rideTypes == CLUSTER) { 
      if (cabiStations[bikeoutStation].inFocus && cabiStations[bikeinStation].inFocus) {category = 1;}
      else if (cabiStations[bikeoutStation].inFocus)                                   {category = 2;}
      else                                                                             {category = 0;} 
      }
    else if (rideTypes == BIKENO) { 
      if (bikeNo.equals("W21852")) {category = 0;}
      else                         {category = 1;} 
      }
    else if (rideTypes == TRIPDAY) {  // check start day
      //println(bikeoutDayTime.get(Calendar.DAY_OF_MONTH));
      if (bikeoutDayTime.get(Calendar.DAY_OF_MONTH) == 9) {category = 0;}
      else                                                {category = 1;} 
      }
    else if (rideTypes == ALL_TYPES)    { 
      if      (membership.equals("24-hour"))                     {category = 0;}
      else if (membership.equals("3-Day"))                       {category = 1;}
      else if (membership.equals("3-Days"))                      {category = 1;}
      else if (membership.equals("30-day"))                      {category = 2;}
      else if (membership.equals("Annual"))                      {category = 3;}
      else if (membership.equals("Annual - Silver"))             {category = 4;}
      else if (membership.equals("Corporate annual membership")) {category = 5;}
      else if (membership.equals("Arlington Resident - Cash Annual Membership - BSS4")) {category = 6;}
      else if (membership.equals("Arlington Resident - Cash Annual Membership with Monthly Installments - BSS4")) {category = 7;}
      else if (membership.equals("Day Key ($7)")) {category = 8;}
      else if (membership.equals("Day Key (initial payment $10")) {category = 9;}
      else if (membership.equals("MCLiberty"))                    {category = 10;}
      else if (membership.equals("Employee"))                     {category = 11;}
      else if (membership.equals("Job Access Reverse Commute Membership - BSS4")) {category = 12;} 
      else                         {println("ERROR: " + membership);} 
      //println(category);
      }
    }     
  } 
  
public class cabiCircle implements Comparable<cabiCircle> { 
  // representation of a CaBi rider on the screen
  public float x, y;
  public int radius;  
  public Boolean selected;
  public cabiCircle(float X, float Y, int R, Boolean B) {
    x = X;
    y = Y;
    radius = R;
    selected = B;
    }
  @Override public int compareTo(cabiCircle that) {  // so that "sort" function will work
    if (this.radius < that.radius) return -1;
    if (this.radius > that.radius) return 1;
    return 0;
    }     
  } 
  
String jurisdictionOfStation(int x) {
  if (x <= 31040) {return "Arlington";}
  if (x <= 31048) {return "Alexandria";}
  if (x <= 31063) {return "Arlington";}
  if (x <= 31064) {return "Alexandria";}
  if (x <= 31080) {return "Arlington";}
  if (x <= 31088) {return "Alexandria";}
  if (x <= 31096) {return "Arlington";}
  if (x <= 31099) {return "Alexandria";}
  if (x <= 31899) {return "DC";}
  if (x <= 31902) {return "Arlington";}
  if (x <= 31903) {return "Alexandria";}
  if (x <= 31905) {return "Arlington";}
  if (x <= 31916) {return "Alexandria";}
  if (x <= 31917) {return "Arlington";}
  if (x <= 31918) {return "Alexandria";}
  if (x <= 31999) {return "Arlington";}
  if (x <= 32058) {return "Montgomery";}
                   return "Fairfax";
  }
  
public class cabiStation { 
  // a single Capital Bikeshare station
  public float lat, lng;  
  public float x, y;
  public String name;  
  public String id;  
  public String jurisdiction;
  int idInt;
  Boolean inUse;  // are ridings currently travelling to or from this station?
  Boolean inFocus;  // does the current dataset include this station?
  List<BikeDirections> directions;  // directions from this station to other stations
  public cabiStation(float latitude, float longitude, String n, String i) {
    lat = latitude;
    lng = longitude;
    name = n;
    id = i;
    idInt = Integer.parseInt(id);
    jurisdiction = jurisdictionOfStation(idInt);
    inUse = false;
    inFocus = false;
    directions = new ArrayList<BikeDirections>();
    } 
  } 

void initSystem(String system) {
  // read in initial data
  String lines[] = loadStrings(system);
  cabiStations = new cabiStation[lines.length];
  for (int i = 0; i < lines.length; i++) {
    String[] fields = lines[i].split(",");
    cabiStations[i] = new cabiStation(parseFloat(fields[1]), parseFloat(fields[2]), fields[0], fields[3]);
    }
  }
  
void initDirections() {
  println("initDirections!");
  paths = new String[cabiStations.length][cabiStations.length];
  for (int i = 0; i < cabiStations.length; i++) {
    for (int j = 0; j < cabiStations.length; j++) {
      paths[i][j] = "";
      }
    } 
  Table table;
  table = loadTable("/Users/michael/mvjantzen.com/cabi/directions/stationdirections.csv", "header, csv"); 
  for (int i = 0; i < table.getRowCount(); i++) {
    TableRow row = table.getRow(i);
    String fromId = row.getString("from");
    //println("fromId = " + fromId);
    int j = stationIndexFromID(fromId);
    if (j < 0) {
      println("Can't find station matching " + fromId);
      }
    else {
      cabiStations[j].directions.add(new BikeDirections(fromId, row.getString("to"), row.getString("points")));
      }
    }
  }

int stationIndexFromID(String id) { 
  int i = cabiStations.length - 1;
  while (i >= 0 && !cabiStations[i].id.equals(id)) {
    i--;
    } 
  return i;
  }

Calendar stringToCalendar(String time) {
  String[] daytime = split(time, " ");
  /* ugh, they changed the date format >:P
  String[] mdy = split(daytime[0], "/");  
  if (mdy.length < 3) {
    mdy = split(daytime[0], "-"); 
    }
  return new GregorianCalendar(parseInt(mdy[2]), parseInt(mdy[0]) - 1, parseInt(mdy[1]), parseInt(hm[0]), parseInt(hm[1]), 0);
  */
  String[] mdy = split(daytime[0], "/");   
  String[] hm = split(daytime[1], ":");
  //println(time);
  //return new GregorianCalendar(2015, 1, 1);
  if (mdy.length < 3) println("BAD DATE (mdy): " + time);
  if (hm.length < 2) println("BAD DATE (hm): " + time);
  // use public GregorianCalendar(year, month (0-based), dayOfMonth (1-based), hourOfDay, minute)
  return new GregorianCalendar(parseInt(mdy[2]), parseInt(mdy[0]) - 1, parseInt(mdy[1]), parseInt(hm[0]), parseInt(hm[1]), 0);
  }

float toY(float lat) {
  return sheight - sheight*(lat - minLat)/(maxLat - minLat);
  }

float toX(float lng) {
  return swidth*(lng - minLng)/(maxLng - minLng);
  }

void drawStations(int f) {
  // f is used only if displayMethod == BALANCES
  /*
  float[] MetroLat = new float[]{38.92434, 38.92063, 38.9215, 38.929167, 38.94786, 38.886867, 38.862388, 38.893348, 38.884327, 38.882247, 38.891550, 38.984053, 38.813033, 38.824041, 38.935411, 38.889673, 38.885014, 38.916197, 38.887453, 38.934643, 38.978195, 38.928689, 38.844710, 38.891558, 38.858088, 38.908263, 38.883159, 38.911115, 38.885987, 38.884713, 38.801343, 38.902654, 38.901324, 38.885058, 38.893602, 38.900678, 39.015227, 38.952546, 38.769150, 38.960786, 38.898423, 38.936089, 39.061430, 39.010914, 39.030641, 38.795260, 38.897359, 38.806706, 38.884920, 38.931665, 38.903610, 38.901292, 38.999617, 38.898327, 38.898409, 38.891764, 38.905210, 38.876418, 38.852389, 38.948038, 38.907265, 38.866934, 38.860511, 38.881194, 38.964943, 38.921641, 39.085454, 38.848824, 38.896595, 39.117151, 38.914135, 38.993658, 38.887577, 38.839907, 38.885332, 38.842801, 38.975008, 38.947057, 39.060759, 38.917029, 38.896255, 38.799271, 38.944229, 38.877219, 38.883428, 38.876391, 38.898705, 38.953420, 39.038442, 39.047101, 38.925105};
  float[] MetroLng = new float[]{-77.21048, -77.22193, -77.2344, -77.241944, -77.34041, -76.898110, -76.995054, -77.021937, -77.063823, -77.111803, -76.939166, -77.094078, -77.053113, -76.911851, -76.992970, -76.913445, -77.005890, -76.915712, -77.094973, -77.058191, -76.926343, -77.032610, -76.988503, -77.084598, -77.051687, -76.933729, -77.228073, -77.044865, -77.156293, -76.996175, -77.072277, -77.039444, -77.039454, -77.015176, -77.028116, -77.050125, -77.042625, -76.997114, -77.171043, -77.085731, -77.021938, -77.024395, -77.052529, -76.910380, -77.105115, -77.072933, -77.017576, -77.059724, -77.021542, -76.889725, -76.841802, -77.032036, -77.097963, -77.027775, -76.946493, -76.864067, -77.021863, -77.004740, -76.956032, -76.871699, -77.003966, -77.056077, -77.059569, -76.985481, -76.953716, -76.994804, -77.146686, -77.045723, -77.071460, -77.164717, -77.021890, -77.032304, -77.028128, -76.977401, -76.977233, -76.932048, -77.016835, -77.079242, -77.120759, -77.029613, -77.007271, -77.130897, -77.063494, -77.272897, -77.103350, -77.017514, -77.185521, -76.965606, -77.050647, -77.112825, -77.052433};
  textAlign(CENTER, CENTER);
  fill(255);
  for (int i = 0; i < MetroLat.length; i++) {  
    text("M", toX(MetroLng[i]), toY(MetroLat[i]));
    }
  */
  // draw all the stations
  int radius;
  int traffic;
  color fillColor;
  if (displayMethod == BALANCES) {
    for (int i = 0; i < cabiStations.length; i++) { 
      radius = round(0.5*sqrt(abs(balanceSum[i])/PI)); 
      if (balanceSum[i] > 0)
        fill(255, 0, 0, 127);
      else
        fill(0, 255, 0, 127);
      if (balanceSum[i] > 0)
        fillColor = color(0, 215, 12, 107);  
      else
        fillColor = color(223, 0, 4, 107);     
      drawCircle(cabiStations[i].x, cabiStations[i].y, fillColor, true, radius);
      } 
    for (int i = 0; i < cabiStations.length; i++) {  
      if (balanceSum[i] > 0)
        fill(0, 223, 8);
      else if (balanceSum[i] < 0)
        fill(223, 0, 8);
      else
        fill(223, 223, 16); 
      ellipse(cabiStations[i].x, cabiStations[i].y, 5, 5);  
      balanceSum[i] += balances[i][f];
      } 
    }
  else if (displayMethod == CHARCOAL) {
    cabiCircle[] circles = new cabiCircle[cabiStations.length];
    strokeWeight(3);
    fill(241, 89, 42);
    int busiestStation = 0;
    int[] tripsToFromStation = new int[cabiStations.length];
    for (int i = 0; i < cabiStations.length; i++) {
      tripsToFromStation[i] = 0;
      for (int j = 0; j < cabiStations.length; j++) {
        traffic = tripRiders[i][j] + tripRidersCas[i][j] + tripRiders[j][i] + tripRidersCas[j][i];
        tripsToFromStation[i] += traffic;
        }
      busiestStation = max(busiestStation, tripsToFromStation[i]);
      } 
      
      /*
    int totaltrips = 0;
    for (int rs = 0; rs < cabiStations.length; rs++) {  
      totaltrips += tripsToFromStation[rs];
    }
    println("total trips: " + totaltrips);
    */
      
    for (int rs = 0; rs < cabiStations.length; rs++) {  
      radius = 1 + round(sqrt(8*tripsToFromStation[rs])); 
      //println(radius +" %%% " + tripsToFromStation[rs]);
      circles[rs] = new cabiCircle(cabiStations[rs].x, cabiStations[rs].y, radius, cabiStations[rs].inFocus);
      }
    Arrays.sort(circles);  // so the smaller circles are drawn on top of the larger circles
    for (int rs = cabiStations.length - 1; rs >= 0; rs--) {
      if (circles[rs].selected) {
        stroke(0, 125, 171);
        fill(255, 255, 255, 127);
        // fill(0, 125, 171, 127);  // KP blue
        }
      else {
        stroke(112);
        fill(224);
        }
      ellipse(circles[rs].x, circles[rs].y, circles[rs].radius, circles[rs].radius);  
      }
    maxBusiest = max(maxBusiest, busiestStation);
    } 
  else {
    strokeWeight(1); 
    int busiestStation = 0;
    int[] tripsToFromStation = new int[cabiStations.length];
    for (int i = 0; i < cabiStations.length; i++) {
      tripsToFromStation[i] = 0;
      for (int j = 0; j < cabiStations.length; j++) {
        traffic = tripRiders[i][j] + tripRidersCas[i][j] + tripRiders[j][i] + tripRidersCas[j][i];
        tripsToFromStation[i] += traffic;
        }
      busiestStation = max(busiestStation, tripsToFromStation[i]);
      //println("tripsToFromStation[" + i + "] = " + tripsToFromStation[i]);
      }
    stroke(0, 0, 0); 
    fill(0, 51, 68);  
    for (int rs = 0; rs < cabiStations.length; rs++) { 
      if (cabiStations[rs].inFocus)
        radius = 2;
      else
        radius = 1; 
      if (cabiStations[rs].inUse) {
        stroke(0, 255);
        fill(204, 255); 
        }
      else {  
        stroke(0, 159);
        fill(204, 159); 
        } 
      stroke(255, 128);
      if (cabiStations[rs].inUse) {
        fill(255, 128); 
        }
      else {   
        fill(0, 128); 
        } 
      //if (cabiStations[rs].inFocus) {radius*=2; fill(204,51,255);} else {radius*=1.5; fill(153,204,51);}
      ellipse(cabiStations[rs].x, cabiStations[rs].y, radius, radius);
      } 
    maxBusiest = max(maxBusiest, busiestStation);
    }
  }   
  
Boolean EastoftheRiver(String s) {
  int x = parseInt(s);
  return (x >= 31700 && x <= 31807);
  }

Boolean isCrystalCity(String s) {
  int x = parseInt(s);
  return (x >= 31000 && x <= 31003) || x == 31007 || (x >= 31009 && x <= 31013) || x == 31052;
  }

Boolean isGreaterCrystalCity(String s) {
  int x = parseInt(s);
  return (x >= 31000 && x <= 31013) || x == 31052 || x == 31071 || x == 31090 || x == 31091;
  }

void drawKey(String timestamp) {
  float scale = 15;  // histogram height
  // write "©Mobility Lab" on side
  textSize(12);
  if (lightmap) fill(  0,   0,   0);
  else          fill(255, 255, 255);
  textAlign(LEFT, BOTTOM);
  pushMatrix();
  translate(swidth - 2, sheight - 4);
  rotate(-HALF_PI);
  text("©Mobility Lab", 0, 0);
  popMatrix();
  // write title
  int TitleY;
  if (displayMethod == SWEEP)
    TitleY = sheight - 53;
  else if (displayMethod == RIDERTYPE)
    TitleY = sheight - 16*statistics.length - 6;
  else
    TitleY = sheight - 37;
  if (showKeyCalculation) {TitleY -= 16;}
  textAlign(RIGHT);
  textSize(18);
  strokeText(movieTitle, swidth - 15, TitleY - 29);
  textSize(14.5);
  strokeText(subTitle, swidth - 15, TitleY - 13);
  textSize(11.5);
  strokeText(dataTitle, swidth - 15, TitleY);
  // write key
  noStroke();
  if (displayMethod == RIDERTYPE) {  
    for (int i = statistics.length - 1; i >= 0; i--) {  // each key
      textAlign(RIGHT);
      strokeText(str(statistics[i].count), swidth - 88, TitleY + 16*i + 15);  
      fill(statistics[i].opaque);
      rect(swidth - 85, TitleY + 16*i + 4, 70, 14, 3);
      textAlign(CENTER);
      fill(0);
      text(statistics[i].label, swidth - 50, TitleY + 16*i + 15);
      // strokeText("(" + str(round(100.0*into[tickCount - 1]/totalTrips)) + "%)", swidth - 82, sheight - 36);  
      }
    if (showKeyCalculation) {
      textAlign(RIGHT);
      strokeText(str(round(100*(statistics[1].count - statistics[0].count)/statistics[0].count)) + "%", swidth - 88, sheight - 6);  
      fill(255, 255, 255);
      rect(swidth - 85, sheight - 17, 70, 14, 3);
      textAlign(CENTER);
      fill(0);
      text("growth", swidth - 50, sheight - 6);
      }
    } 
  else if (displayMethod == SWEEP) {
    textAlign(RIGHT);
    textSize(12);
    strokeText(timestamp, swidth - 15, sheight - 4);
    strokeText(str(statistics[1].histogram[tickCount - 1]), swidth - 86, sheight - 19); // should be from current data, not histogram - FIX
    strokeText(str(statistics[0].histogram[tickCount - 1]), swidth - 86, sheight - 35); 
    fill(statistics[0].fill);
    noStroke();
    rect(swidth - 84, sheight - 32, 70, 14, 3);
    fill(statistics[1].fill);
    rect(swidth - 84, sheight - 47, 70, 14, 3);
    fill(255);
    textAlign(CENTER);
    text("registered", swidth - 49, sheight - 19);
    text("casual", swidth - 49, sheight - 35);
    }
  else if (displayMethod == BALANCES) {
    textSize(14);
    strokeText(timestamp, swidth - 15, sheight - 9);
    }
  else if (displayMethod == CHARCOAL) { 
    textSize(28);
    strokeText(timestamp, swidth - 15, sheight - 9); 
    } 
  // draw the histogram
  strokeWeight(1); 
  noFill();
  int barBottom, barTop;
  int histoLeft = 8;
  int histoBottom = sheight - 19;
  if (showKeyCalculation) {histoBottom -= 50;}
  if (statistics.length == 0) {tickCount = 0;}  // this belongs elsewhere... better to not hit tickcount++?
  for (int h = 0; h < tickCount; h++) {  
    int barX = histoLeft + h;
    stroke(statistics[0].opaque);
    line(barX, sheight - 116, barX, sheight - 116 - (float)statistics[0].histogram[h]/scale);  
    stroke(statistics[1].opaque);
    line(barX, sheight - 115, barX, sheight - 115 + (float)statistics[1].histogram[h]/scale);  
    if (showKeyCalculation) {
      stroke(255, 255, 255);
      line(barX, sheight - 8, barX, sheight - 8 - 40.0*(float)(statistics[1].histogram[h] - statistics[0].histogram[h])/(float)statistics[0].histogram[h]);  
      }
    }
  /*
  for (int h = 0; h < tickCount; h++) { 
    barTop = histoBottom;
    int barX = histoLeft + h;
    for (int i = statistics.length - 1; i >= 0; i--) {  // each key
      barBottom = barTop;
      barTop = barBottom - round((float)statistics[i].histogram[h]/scale);
      stroke(statistics[i].opaque);
      line(barX, barBottom, barX, barTop + 1);  
      } 
    if (showKeyCalculation) {
      stroke(255, 255, 255);
      line(barX, sheight - 8, barX, sheight - 8 - 40.0*(float)(statistics[1].histogram[h] - statistics[0].histogram[h])/(float)statistics[0].histogram[h]);  
      }
    }
    */
  textSize(12);
  textAlign(CENTER);
  strokeText(timestamp, histoLeft + tickCount, histoBottom + 16); 
  }

String toHHMM(int seconds) {
  int hours = floor(seconds/3600);
  seconds -= hours*3600;
  int mins = floor(seconds/60);
  String hh;
  String mm;
  if (hours < 10) 
    hh = "0" + str(hours);
  else
    hh = str(hours);
  if (mins < 10) 
    mm = "0" + str(mins);
  else
    mm = str(mins);
  return hh + ":" + mm;
  }

int secondsPastMidnight(String time) { 
  // return the number of seconds since midnight
  String[] daytime = split(time, " ");
  //String[] mdy = split(daytime[0], "/"); 
  String[] hm = split(daytime[1], ":");
  return 3600*parseInt(hm[0]) + 60*parseInt(hm[1]);
  } 

void partialBezier(float t0, float t1, float x1, float y1, float bx1, float by1, float bx2, float by2, float x2, float y2) {  
  float u0 = 1.0 - t0;
  float u1 = 1.0 - t1;
  float qxa =  x1*u0*u0 + bx1*2*t0*u0 + bx2*t0*t0;
  float qxb =  x1*u1*u1 + bx1*2*t1*u1 + bx2*t1*t1;
  float qxc = bx1*u0*u0 + bx2*2*t0*u0 +  x2*t0*t0;
  float qxd = bx1*u1*u1 + bx2*2*t1*u1 +  x2*t1*t1;
  float qya =  y1*u0*u0 + by1*2*t0*u0 + by2*t0*t0;
  float qyb =  y1*u1*u1 + by1*2*t1*u1 + by2*t1*t1;
  float qyc = by1*u0*u0 + by2*2*t0*u0 +  y2*t0*t0;
  float qyd = by1*u1*u1 + by2*2*t1*u1 +  y2*t1*t1;
  float xa = qxa*u0 + qxc*t0;
  float xb = qxa*u1 + qxc*t1;
  float xc = qxb*u0 + qxd*t0;
  float xd = qxb*u1 + qxd*t1;
  float ya = qya*u0 + qyc*t0;
  float yb = qya*u1 + qyc*t1;
  float yc = qyb*u0 + qyd*t0;
  float yd = qyb*u1 + qyd*t1; 
  bezier(xa, ya, xb, yb, xc, yc, xd, yd); 
  }
  
void gradientBezier(float x1, float y1, float midx, float midy, float x2, float y2) {  
  stroke(255,0,0,40); partialBezier(0.0, 0.0833, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(250,0,0,48); partialBezier(0.0833, 0.1667, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(245,0,0,56); partialBezier(0.1667, 0.25, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(240,0,0,64); partialBezier(0.25, 0.3333, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(235,0,0,72); partialBezier(0.3333, 0.4167, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(230,0,0,80); partialBezier(0.4167, 0.5, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(225,0,0,88); partialBezier(0.5, 0.5833, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(220,0,0,96); partialBezier(0.5833, 0.6667, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(215,0,0,104); partialBezier(0.6667, 0.75, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(210,0,0,112); partialBezier(0.75, 0.8333, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(205,0,0,120); partialBezier(0.8333, 0.9167, x1, y1, midx,midy,midx,midy, x2, y2);
  stroke(200,0,0,128); partialBezier(0.9167, 1.0, x1, y1, midx,midy,midx,midy, x2, y2);
  }
  
void strokeText(String message, int x, int y) { 
  if (lightmap) {
    fill(255); 
    text(message, x-2, y); 
    text(message, x, y-2); 
    text(message, x+2, y); 
    text(message, x, y+2); 
    fill(0); 
    text(message, x, y); 
    }
  else {
    fill(0);  
    text(message, x+2, y+2);  
    fill(255); 
    text(message, x, y); 
    }
  } 

Boolean gameday(int day) {
  Boolean[] hasGame = new Boolean[366];
  for (int i = 0; i < hasGame.length; i++) {
    hasGame[i] = false;
    }
  String[] dates = {
"4/6/2015",
"4/8/2015",
"4/9/2015",
"4/16/2015",
"4/17/2015",
"4/18/2015",
"4/19/2015",
"4/21/2015",
"4/22/2015",
"4/23/2015",
"5/4/2015",
"5/5/2015",
"5/6/2015",
"5/8/2015",
"5/9/2015",
"5/10/2015",
"5/19/2015",
"5/20/2015",
"5/22/2015",
"5/23/2015",
"5/24/2015",
"6/1/2015",
"6/2/2015",
"6/2/2015",
"6/3/2015",
"6/4/2015",
"6/5/2015",
"6/6/2015",
"6/7/2015",
"6/17/2015",
"6/18/2015",
"6/19/2015",
"6/20/2015",
"6/21/2015",
"6/23/2015",
"6/24/2015",
"6/25/2015",
"7/3/2015",
"7/4/2015",
"7/5/2015",
"7/6/2015",
"7/7/2015",
"7/8/2015",
"7/17/2015",
"7/18/2015",
"7/18/2015",
"7/19/2015",
"7/20/2015",
"7/21/2015",
"7/22/2015",
"8/3/2015",
"8/4/2015",
"8/5/2015",
"8/6/2015",
"8/7/2015",
"8/8/2015",
"8/9/2015",
"8/21/2015",
"8/22/2015",
"8/23/2015",
"8/25/2015",
"8/26/2015",
"8/27/2015",
"8/28/2015",
"8/29/2015",
"8/30/2015",
"9/3/2015",
"9/4/2015",
"9/5/2015",
"9/6/2015",
"9/7/2015",
"9/8/2015",
"9/9/2015",
"9/17/2015",
"9/18/2015",
"9/19/2015",
"9/20/2015",
"9/21/2015",
"9/22/2015",
"9/23/2015",
"9/24/2015",
"9/25/2015",
"9/26/2015",
"9/27/2015",
"9/28/2015"};  
  for (int i = 0; i < dates.length; i++) {  
    String[] mdy = split(dates[i], "/");   
    Calendar calendar = new GregorianCalendar(parseInt(mdy[2]), parseInt(mdy[0]) - 1, parseInt(mdy[1]), 0, 0, 0);
    hasGame[calendar.get(Calendar.DAY_OF_YEAR)] = true;
    }
  return hasGame[day];
  }
  
void getStats() {
  HashMap<String, Integer> zipCounts = new HashMap<String, Integer>();
  println("calculating stats...");
  List<CaBiBike> bikeList = new ArrayList<CaBiBike>(2000);  // assume no more than 2000 bikes
  CaBiTrip trip;
  SimpleDateFormat format1 = new SimpleDateFormat("yyyy-MM-dd");
  int toCC = 0;
  int toArl = 0;
  int toAlex = 0;
  int toDC = 0;
  int toMD = 0;
  int fromSelection = 0;
  int[] maleTripsPerStation = new int[cabiStations.length];
  int[] femaleTripsPerStation = new int[cabiStations.length];
  int[] cat0castripsPerStation = new int[cabiStations.length];
  int[] cat1castripsPerStation = new int[cabiStations.length];
  int[] cat0regtripsPerStation = new int[cabiStations.length];
  int[] cat1regtripsPerStation = new int[cabiStations.length];
  int[] regWeekendTripsPerStation = new int[cabiStations.length];
  int[] casWeekendTripsPerStation = new int[cabiStations.length];
  int[] tripsPerDayOfYear = new int[366];
  int[] tripsPerWeekOfYear = new int[53];
  int[] tripsPerMonth = new int[12];
  int[] tripsPerDayOfYearBaseball = new int[366]; 
  int[] tripsPerDayOfYearNonBaseball = new int[366]; 
  int[] tripsPerStation = new int[cabiStations.length]; 
  int[] tripsToFromLincolnMemorial = new int[cabiStations.length]; 
  String[] stringTrips = new String[cabiStations.length]; 
  int[] casualTripsPerStation = new int[cabiStations.length]; 
  int totalTrips = 0;
  int totalCasualTrips = 0;
  int LincolnToJefferson = 0;
  int JeffersonToLincoln = 0;
  Calendar calendar;
  for (int i = 0; i < tripsPerDayOfYear.length; i++) {
    tripsPerDayOfYear[i] = 0;
    tripsPerDayOfYearBaseball[i] = 0; 
    tripsPerDayOfYearNonBaseball[i] = 0; 
    }
  for (int i = 0; i < tripsPerMonth.length; i++) {
    tripsPerMonth[i] = 0; 
    }
  for (int i = 0; i < tripsPerWeekOfYear.length; i++) {
    tripsPerWeekOfYear[i] = 0; 
    }
  for (int i = 0; i < tripsPerStation.length; i++) {
    tripsPerStation[i] = 0;
    casualTripsPerStation[i] = 0;
    tripsToFromLincolnMemorial[i] = 0;
    cat0castripsPerStation[i] = 0;
    cat1castripsPerStation[i] = 0;
    cat0regtripsPerStation[i] = 0;
    cat1regtripsPerStation[i] = 0;
    regWeekendTripsPerStation[i] = 0;
    casWeekendTripsPerStation[i] = 0;
    maleTripsPerStation[i] = 0;
    femaleTripsPerStation[i] = 0;
    }
  println(validTrips.size() + " trips...");
  for (int t = 0; t < validTrips.size(); t++) {  
    trip = validTrips.get(t); 
    if (!zipCounts.containsKey(trip.memberZip)) {
      zipCounts.put(trip.memberZip, 1);
      } 
    else { 
      zipCounts.put(trip.memberZip, zipCounts.get(trip.memberZip) + 1);
      }
    if (trip.gender == 'M') {
      maleTripsPerStation[trip.bikeinStation]++;
      maleTripsPerStation[trip.bikeoutStation]++;
      }
    else if (trip.gender == 'F') {
      femaleTripsPerStation[trip.bikeinStation]++;
      femaleTripsPerStation[trip.bikeoutStation]++;
      }
    //if (t % 10000 == 0) println(format1.format(trip.bikeoutDayTime.getTime()) + " --- " + trip.bikeoutDayTime.get(Calendar.DAY_OF_YEAR));
    int bikeoutDayOfYear = trip.bikeoutDayTime.get(Calendar.DAY_OF_YEAR);  // Jan 1 = 1, not 0
    int bikeinDayOfYear = trip.bikeinDayTime.get(Calendar.DAY_OF_YEAR);
    int dayOfWeek = trip.bikeoutDayTime.get(Calendar.DAY_OF_WEEK);
    if (dayOfWeek == Calendar.SATURDAY || dayOfWeek == Calendar.SUNDAY || true) {
      if (trip.isRegistered) {
        regWeekendTripsPerStation[trip.bikeinStation]++;
        regWeekendTripsPerStation[trip.bikeoutStation]++;
        }
      else {
        casWeekendTripsPerStation[trip.bikeinStation]++;
        casWeekendTripsPerStation[trip.bikeoutStation]++;
        }
      }
    tripsPerDayOfYear[bikeoutDayOfYear - 1]++;  
    tripsPerWeekOfYear[floor((bikeoutDayOfYear - 1)/7)]++; 
    tripsPerMonth[trip.bikeoutDayTime.get(Calendar.MONTH)]++; 
    if (trip.category == 0) {
      if (trip.isRegistered) {
        cat0regtripsPerStation[trip.bikeinStation]++;
        cat0regtripsPerStation[trip.bikeoutStation]++;
        }
      else {
        cat0castripsPerStation[trip.bikeinStation]++;
        cat0castripsPerStation[trip.bikeoutStation]++;
        }
      }
    else if (trip.category == 1) {
      if (trip.isRegistered) {
        cat1regtripsPerStation[trip.bikeinStation]++;
        cat1regtripsPerStation[trip.bikeoutStation]++;
        }
      else {
        cat1castripsPerStation[trip.bikeinStation]++;
        cat1castripsPerStation[trip.bikeoutStation]++;
        }
      }
    if (cabiStations[trip.bikeoutStation].id.equals("31258")) {
      tripsToFromLincolnMemorial[trip.bikeinStation]++;
      }
    if (cabiStations[trip.bikeinStation].id.equals("31258")) {
      tripsToFromLincolnMemorial[trip.bikeoutStation]++;
      }
    if (cabiStations[trip.bikeoutStation].id.equals("31209") || 
        cabiStations[trip.bikeoutStation].id.equals("31634") || 
        cabiStations[trip.bikeoutStation].id.equals("31208")) {
      if (gameday(bikeoutDayOfYear)) {tripsPerDayOfYearBaseball[bikeoutDayOfYear - 1]++;}
      else                           {tripsPerDayOfYearNonBaseball[bikeoutDayOfYear - 1]++;}
      }   
    if (cabiStations[trip.bikeinStation].id.equals("31209") || 
        cabiStations[trip.bikeinStation].id.equals("31634") || 
        cabiStations[trip.bikeinStation].id.equals("31208")) {
      if (gameday(bikeinDayOfYear)) {tripsPerDayOfYearBaseball[bikeinDayOfYear - 1]++;}
      else                          {tripsPerDayOfYearNonBaseball[bikeinDayOfYear - 1]++;}
      }   
    
    Boolean found = false;
    for (int i = 0; i < bikeList.size(); i++) {
      if (bikeList.get(i).bikeID.equals(trip.bikeNo)) {
        bikeList.get(i).trips++;
        found = true;
        }
      }
    if (!found) {
      bikeList.add(new CaBiBike(trip.bikeNo));
      }
    if (cabiStations[trip.bikeoutStation].id.equals("31258") && cabiStations[trip.bikeinStation].id.equals("31249")) {LincolnToJefferson++;}
    if (cabiStations[trip.bikeoutStation].id.equals("31249") && cabiStations[trip.bikeinStation].id.equals("31258")) {JeffersonToLincoln++;}
    if (isGreaterCrystalCity(cabiStations[trip.bikeoutStation].id)) {
      if (isGreaterCrystalCity(cabiStations[trip.bikeinStation].id)) toCC++;
      else if (cabiStations[trip.bikeinStation].jurisdiction.equals("DC"))         toDC++; 
      else if (cabiStations[trip.bikeinStation].jurisdiction.equals("Arlington"))  toArl++;
      else if (cabiStations[trip.bikeinStation].jurisdiction.equals("Alexandria")) toAlex++;
      else if (cabiStations[trip.bikeinStation].jurisdiction.equals("Montgomery")) toMD++;
      fromSelection++;
      }
    if (!trip.isRegistered) {
      casualTripsPerStation[trip.bikeoutStation]++;
      casualTripsPerStation[trip.bikeinStation]++;
      }
    tripsPerStation[trip.bikeinStation]++;
    tripsPerStation[trip.bikeoutStation]++;
    }
  println("all weekend trips per station:");
  for (int i = 0; i < tripsPerStation.length; i++) {
    stringTrips[i] = String.format("%7d", casWeekendTripsPerStation[i] + regWeekendTripsPerStation[i]) + "," + casWeekendTripsPerStation[i] + "," + regWeekendTripsPerStation[i] + "," + cabiStations[i].name; 
    }
  for (int i = 0; i < femaleTripsPerStation.length; i++) {
    if (femaleTripsPerStation[i] + maleTripsPerStation[i] > 9)
    stringTrips[i] = String.format("%7d", 100*femaleTripsPerStation[i]/(femaleTripsPerStation[i] + maleTripsPerStation[i])) + ":=: " + cabiStations[i].name + "; " + femaleTripsPerStation[i] + " Fs " + maleTripsPerStation[i] + " Ms";
   else stringTrips[i] = "";
    }
  println(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"); 
  println("trips (from) per Month of year:"); 
  for (int i = 0; i < tripsPerMonth.length; i++) {
    Calendar working = GregorianCalendar.getInstance();
    working.set(2016, i, 1);   
    println(String.format("%07d", tripsPerMonth[i]) + ": " + format1.format(working.getTime()));
    }
  Arrays.sort(stringTrips);
  for (int i = stringTrips.length - 1; i >= 0; i--) {
    //println(stringTrips[i]);
    }
  println(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"); 
  println("trips (from) per day of year:"); 
  for (int i = 0; i < tripsPerDayOfYear.length; i++) {
    Calendar working = GregorianCalendar.getInstance();
    working.set(2016, 0, 1);  // Jan 1, 2016
    working.add(Calendar.DAY_OF_YEAR, i); 
    //println(String.format("%07d", tripsPerDayOfYear[i]) + ": " + format1.format(working.getTime()));
    //println(format1.format(working.getTime()) + "," + tripsPerDayOfYearBaseball[i] + "," + tripsPerDayOfYearNonBaseball[i]);
    }
    /*
  println("increase in trips per station:");
  for (int i = 0; i < tripsPerStation.length; i++) {
    stringTrips[i] = String.format("%7d", tripsPerStation[i]) + "," + cabiStations[i].id;
    totalTrips += tripsPerStation[i];
    totalCasualTrips += casualTripsPerStation[i];
    float growth;
    if (cat0tripsPerStation[i] == 0) {
      growth = 0;
      }
    else {
      //growth = 100.0*(float)(cat1tripsPerStation[i] - cat0tripsPerStation[i])/(float)cat0tripsPerStation[i];
      }
    //if (growth >= 10.0 && cat1tripsPerStation[i] >= 100)
      //println(growth + "% " + cabiStations[i].name + " (" +cat0tripsPerStation[i] + " to " + cat1tripsPerStation[i] + ")");
    println("{id:" + cabiStations[i].id + ",name:\"" + cabiStations[i].name + "\"," + 
      "Mar9cas:" +cat0castripsPerStation[i] + ",Mar16cas:" + cat1castripsPerStation[i] + "," + 
      "Mar9reg:" +cat0regtripsPerStation[i] + ",Mar16reg:" + cat1regtripsPerStation[i] + "," + 
      "lat:" + cabiStations[i].lat + ",lng:" + cabiStations[i].lng + "},");
    }
  */
  println("trips (to and from) per station:");
  for (int i = 0; i < tripsPerStation.length; i++) {
    stringTrips[i] = String.format("%7d", tripsPerStation[i]) + ": " + cabiStations[i].name + " (" + cabiStations[i].jurisdiction + ")";
    totalTrips += tripsPerStation[i];
    totalCasualTrips += casualTripsPerStation[i];
    }
  Arrays.sort(stringTrips);
  for (int i = stringTrips.length - 1; i >= 0; i--) {
    println(stringTrips[i]);
    }
  int total = 0;
  /*
  for (int i = tripsPerStation.length - 1; i >= 0; i--) {
    String[] tokens = stringTrips[i].trim().split(",");
    total += Integer.parseInt(tokens[0]);
    println(tokens[1] + ":" + tokens[0] + ",");
    println(round(1000.0*casualTripsPerStation[i]/tripsPerStation[i])/10.0 + ": " + cabiStations[i].name + " (" + tripsPerStation[i] + ")");
    }
    */
  int minLMtrips = tripsToFromLincolnMemorial[0];
  int maxLMtrips = tripsToFromLincolnMemorial[0];
  println("trips (to and from) Lincoln Memorial:");
  for (int i = 0; i < tripsToFromLincolnMemorial.length; i++) {
    minLMtrips = min(minLMtrips, tripsToFromLincolnMemorial[i]);
    maxLMtrips = max(maxLMtrips, tripsToFromLincolnMemorial[i]);
    //println("{trips:" + tripsToFromLincolnMemorial[i] + ",name:\"" + cabiStations[i].name + "\",lat:" + cabiStations[i].lat + ",lng:" + cabiStations[i].lng + "},");
    }
  println("min trips: " + minLMtrips + ", max trips: " + maxLMtrips);
  println(round(1000.0*totalCasualTrips/totalTrips)/10.0 + ": TOTAL (" + totalTrips + ")");
  println("***********************************");
  println(LincolnToJefferson + " LincolnToJefferson");
  println(JeffersonToLincoln + " JeffersonToLincoln");
  println(toCC + " toCC (" + (float)toCC/fromSelection + ")");
  println(toArl + " toArl (" + (float)toArl/fromSelection + ")");
  println(toAlex + " toAlex (" + (float)toAlex/fromSelection + ")");
  println(toDC + " toDC (" + (float)toDC/fromSelection + ")");
  println(toMD + " toMD (" + (float)toMD/fromSelection + ")");
  println(fromSelection + " total");
  println("***********************************");
  println((totalTrips - totalCasualTrips) + " registered trips (" + 100.0*(totalTrips - totalCasualTrips)/totalTrips + "%)");
  println(totalCasualTrips + " casual trips (" + 100.0*totalCasualTrips/totalTrips + "%)");
  println(totalTrips + " total trips");
  int maxtrips = 0;
  String busyBike = "";
  println("***********************************");
  for (int i = 0; i < bikeList.size(); i++) {
    //if (bikeList.get(i).bikeID.equals("W20167"))
    //  println(bikeList.get(i).trips + " - " + bikeList.get(i).bikeID);
    if (!bikeList.get(i).bikeID.equals("W21735") && !bikeList.get(i).bikeID.equals("W21705") && !bikeList.get(i).bikeID.equals("W21852") && !bikeList.get(i).bikeID.equals("W21953") && bikeList.get(i).trips > maxtrips) {
      maxtrips = bikeList.get(i).trips;
      busyBike = bikeList.get(i).bikeID;
      }
    }
  println("***********************************");
  println("busy bike is " + busyBike + ", " + maxtrips + "trips");
  println("***********************************");
  for (String string : zipCounts.keySet()) {
    //println(zipCounts.get(string) + " :: " + string);
    }
  }

void setBoundary(String background, float south, float west, float north, float east, int w, int h, List<String> validStations, String s) {  
  bg = loadImage(background); 
  minLng = west;  // left
  maxLng = east;  // right
  minLat = south;  // bottom
  maxLat = north;   // top
  swidth = w;
  sheight = h; 
  for (int i = 0; i < cabiStations.length; i++) {
    cabiStations[i].inFocus = validStations.contains(cabiStations[i].id);
    cabiStations[i].x = toX(cabiStations[i].lng);
    cabiStations[i].y = toY(cabiStations[i].lat);
    }
  movieTitle = s; 
  }

Boolean validStation(String name) {
  return !name.equals("Alta Tech Office") && !name.equals("1714 Warehouse ") && !name.equals("Mo Co Warehouse");
  }

int findMatch(String[] haystack, String needle) {
  int pos = 0;
  while (pos < haystack.length && !haystack[pos].equals(needle)) {
    pos++;
    }
  if (pos < haystack.length) {
    return pos;
    }
  println("Failed to find " + needle);
  return -1;
  }

void setDatasource(String csvFile) {
  String trips[];
  int stationA;
  int stationB;
  String outName;
  String inName;
  String bikeNo;
  trips = loadStrings(csvFile);
  String[] colheaders = split(trips[0], ","); 
  int newCount = 0;
  int outStation = findMatch(colheaders, "Start station");
  int inStation = findMatch(colheaders, "End station");
  int outStationID = findMatch(colheaders, "Start station number");
  int inStationID = findMatch(colheaders, "End station number");
  int outTime = findMatch(colheaders, "Start date");
  int inTime = findMatch(colheaders, "End date");
  int reg = findMatch(colheaders, "Member Type");
  if (reg < 0) {reg = findMatch(colheaders, "Member type");}
  if (reg < 0) {reg = findMatch(colheaders, "Subscription type");}
  if (reg < 0) {reg = findMatch(colheaders, "Subscription Type");}
  if (reg < 0) {reg = findMatch(colheaders, "Account type");}
  int idNo = findMatch(colheaders, "Bike number");
  if (idNo < 0) {idNo = findMatch(colheaders, "Bike #");}
  int memberZip = findMatch(colheaders, "Member's zip/postal code") + 2;
  int memberSex = findMatch(colheaders, "Member's gender") + 2;
  println("outTime: " + outTime);
  println("inTime: " + inTime);
  println("outStationID: " + outStationID);
  println("outStation: " + outStation);
  println("inStationID: " + inStationID);
  println("inStation: " + inStation);
  println("idNo: " + idNo);
  println("reg: " + reg);
  println("memberSex: " + memberSex);
  println("memberZip: " + memberZip);
  println("reading in " + trips.length + " lines");
  for (int t = 1; t < trips.length; t++) {
    if (t % 500000 == 0) println("line " + t);
    String noquotes = trips[t].replace("\"", "");
    String[] cols = split(noquotes, ",");
    stationA = 0;
    stationB = 0;
    outName = cols[outStation];  
    inName = cols[inStation];
    if (idNo >= 0) {
      bikeNo = cols[idNo];
      }
    else {
      bikeNo = "";
      } 
    // 31209, 31634, 31208 are the 3 main baseball stadium stations
    //if (!outId.equals("32901") && !outId.equals("32900") && !inId.equals("32901") && !inId.equals("32900")) {  // skip warehouse trips
    if (validStation(outName) && validStation(inName)) {  // skip warehouse trips 
      while (stationA < cabiStations.length && !cabiStations[stationA].name.equals(outName)) stationA++;
      while (stationB < cabiStations.length && !cabiStations[stationB].name.equals(inName)) stationB++; 
      if (stationA >= cabiStations.length || stationB >= cabiStations.length) {
        println("ERROR: BAD STATION: " + trips[t] + ", " + stationA + ", " + stationB);
        }
      //else if ((stationInFocus[stationA] || stationInFocus[stationB]) && pathMightBeInImage(stationA, stationB)) {
      else if (cabiStations[stationA].inFocus || cabiStations[stationB].inFocus) {
        validTrips.add(new CaBiTrip(stationA, stationB, cols[outTime], cols[inTime], cols[reg], bikeNo, cols[memberZip], cols[memberSex]));
        newCount++; 
        }  
      }
    }
  println(newCount + " trips added from " + csvFile);
  }
  
List<String> crystalCity() {
  List<String> list = new ArrayList<String>();
  int id;
  for (int i = 0; i < cabiStations.length; i++) {
    id = parseInt(cabiStations[i].id);
    if ((id >= 31000 && id <= 31003) || id == 31007 || (id >= 31009 && id <= 31013) || id == 31052)
      list.add(cabiStations[i].id); 
    }
  return list;
  }
  
List<String> all() {
  List<String> list = new ArrayList<String>(); 
  for (int i = 0; i < cabiStations.length; i++) 
    list.add(cabiStations[i].id);  
  return list;
  }
  
List<String> greaterCrystalCity() {
  List<String> list = new ArrayList<String>();
  int id;
  for (int i = 0; i < cabiStations.length; i++) {
    id = parseInt(cabiStations[i].id);
    if ((id >= 31000 && id <= 31013) || id == 31052 || id == 31071 || id == 31090 || id == 31091)
      list.add(cabiStations[i].id); 
    }
  return list;
  }
  
List<String> arlington() {
  List<String> list = new ArrayList<String>();
  for (int i = 0; i < cabiStations.length; i++) {
    if (cabiStations[i].jurisdiction.equals("Arlington"))
      list.add(cabiStations[i].id); 
    }
  return list;
  } 
  
List<String> alexandria() {
  List<String> list = new ArrayList<String>();
  for (int i = 0; i < cabiStations.length; i++) {
    if (cabiStations[i].jurisdiction.equals("Alexandria"))
      list.add(cabiStations[i].id); 
    }
  return list;
  } 
  
List<String> maryland() {
  List<String> list = new ArrayList<String>();
  for (int i = 0; i < cabiStations.length; i++) {
    if (cabiStations[i].jurisdiction.equals("Montgomery"))
      list.add(cabiStations[i].id); 
    }
  return list;
  } 
  
List<String> dc() {
  List<String> list = new ArrayList<String>();
  int id;
  for (int i = 0; i < cabiStations.length; i++) {
    id = parseInt(cabiStations[i].id);
    if (id > 31096 && id < 32000)
      list.add(cabiStations[i].id); 
    }
  return list;
  } 

List<String> centerForTotalHealth() {
  List<String> list = new ArrayList<String>();
  list.add("31616"); 
  list.add("31623"); 
  return list;
  } 
  
List<String> gmu() {
  List<String> list = new ArrayList<String>();
  list.add("31040");  
  return list;
  }
  
List<String> crystalCityMetro() {
  List<String> list = new ArrayList<String>();
  list.add("31007");  
  return list;
  }
  
List<String> dupont() {
  List<String> list = new ArrayList<String>();
  list.add("31200");  // 31200
  return list;
  }
  
List<String> unionstation() {  // 31639 is 2nd & G NE; 31623 is Union Station
  List<String> list = new ArrayList<String>();
  list.add("31623");  
  return list;
  }
  
List<String> lincoln() {
  List<String> list = new ArrayList<String>();
  list.add("31258");  
  return list;
  }
  
List<String> gallaudet() {
  List<String> list = new ArrayList<String>();
  list.add("31508");  
  return list;
  }
  
List<String> jefferson() {
  List<String> list = new ArrayList<String>(cabiStations.length);
  list.add("31249");  
  return list;
  } 
  
List<String> rosslyn() {
  List<String> list = new ArrayList<String>(cabiStations.length);
  list.add("31014"); 
  list.add("31015"); 
  /*
  list.add(31016);
  list.add(31018); 
  list.add(31027);
  list.add(31031);   
  list.add(31051); 
  list.add(31077); 
  list.add(31080); 
  list.add(31093); 
  */
  return list;
  }

color blend(color A, color B, float factor) {  
  // factor = 0.0: all A
  // factor = 0.5: half A + half B
  // factor = 1.0: all B
  return color(red(A) + round(factor*(red(B) - red(A))), 
               green(A) + round(factor*(green(B) - green(A))), 
               blue(A) + round(factor*(blue(B) - blue(A))), 
               alpha(A) + round(factor*(alpha(B) - alpha(A))));   
  }

void findBusiestRoutes() { 
  for (int i = 0; i < cabiStations.length; i++) {
    if (cabiStations[i].inFocus) { 
      for (int j = 0; j < cabiStations.length; j++) 
      mostRidersPerStation = max(mostRidersPerStation, tripRiders[i][j] + tripRidersCas[i][j]); 
      }
    }
  }
  
void drawRoutes() {
  // draw all of the bezier curves, behind the other objects
  if (displayMethod == BALANCES)
    return;
  float midx, midy;
  int totalRiders;
  noFill();  
  for (int i = 0; i < cabiStations.length; i++) {
    for (int j = 0; j < cabiStations.length; j++) {
      if (i != j)  { 
        midx = tripControlX[i][j];
        midy = tripControlY[i][j];
        totalRiders = tripRiders[i][j] + tripRidersCas[i][j];
        if (totalRiders > 0 && mostRidersPerStation > 0) {  
          if (displayMethod == CHARCOAL) {
            strokeWeight(3); 
            stroke(0,0,0, min(255, floor(256.0*5*totalRiders/192)));  // FIX: pre-calculate max val
            } 
          else {
            strokeWeight(totalRiders); 
            // need new way to blend multiple colors based on their percentages:
            //stroke(blend(c1t, c2t, (float)tripRidersCas[i][j]/totalRiders));  
            stroke(blend(statistics[0].stroke, statistics[1].stroke, (float)tripRidersCas[i][j]/totalRiders));  
            } 
          bezier(cabiStations[i].x, cabiStations[i].y, midx,midy,midx,midy, cabiStations[j].x, cabiStations[j].y); 
          } 
        }
      }
    }
  } 
  
void drawRiders(int frame) {
  // draw approximate rider positions, on top of bezier curves
  // frame is in seconds
  if (displayMethod == BALANCES)
    return;
  CaBiTrip trip;
  int outTime, inTime;
  color dotColor;
  color dotColorStroke;
  strokeWeight(2);
  int riderCount = 0;
  for (int t = 0; t < validTrips.size(); t++) {
    trip = validTrips.get(t);
    outTime = trip.bikeoutTime;
    inTime = trip.bikeinTime;  
    if (trip.acrossMidnight && frame < outTime - 15) {
      outTime -= SECONDSperDAY;
      inTime -= SECONDSperDAY;  
      }
    if (frame >= outTime - 15 && frame <= inTime + 15) {
      //println(outTime + " : " + frame + " : " + inTime);
      // determine the color
      if (displayMethod == RIDERTYPE) {
        if (rideTypes == JURISDICTION || rideTypes == CLUSTER || rideTypes == BIKENO || rideTypes == TRIPDAY || rideTypes == ALL_TYPES) {
          statistics[trip.category].count++;
          } 
        else if (rideTypes == CASUAL_REGISTERED && trip.isRegistered || rideTypes == WEEKDAY_WEEKEND && trip.isWeekday) {
          tripRiders[trip.bikeoutStation][trip.bikeinStation]++;
          statistics[1].count++;
          }
        else {
          tripRidersCas[trip.bikeoutStation][trip.bikeinStation]++;
          statistics[0].count++;
          } 
        }
      else {
        if (trip.isRegistered) {
          tripRiders[trip.bikeoutStation][trip.bikeinStation]++; 
          //println("++!");
          }
        else {
          tripRidersCas[trip.bikeoutStation][trip.bikeinStation]++; 
          } 
        }
      riderCount++;
      // if (min(frame, inTime) - outTime < 1800) noFill(); // under 30-min time limit, but don't turn red after bikein 
      if (displayMethod != CHARCOAL) {
        fill(statistics[trip.category].fill); 
        stroke(statistics[trip.category].stroke);
        float scale = (float)(frame - outTime)/(float)(inTime - outTime);  
        drawPointAlongPath(trip, scale, 6); 
        //println("riderCount " + riderCount + ": " + riderCount);
        }
      } 
    } 
  //println("frame " + frame + ": " + riderCount);
  }

void drawPointAlongPath(CaBiTrip trip, float scale, int size) {
  // scale shows position between start/end points (0 to 1)
  int bikeoutStation = trip.bikeoutStation;
  int bikeinStation  = trip.bikeinStation;
  BikeDirections directions = trip.bikeDirections;
  if (scale < 0) {scale = 0; size /= 2;}
  if (scale > 1) {scale = 1; size /= 2;}
  /*
  float midx = tripControlX[bikeoutStation][bikeinStation];
  float midy = tripControlY[bikeoutStation][bikeinStation];
  float x = bezierPoint(cabiStations[bikeoutStation].x, midx, midx, cabiStations[bikeinStation].x, scale);
  float y = bezierPoint(cabiStations[bikeoutStation].y, midy, midy, cabiStations[bikeinStation].y, scale);
  ellipse(x, y, size, size);
  */
  if (directions != null) {  // directions exist 
    int j = 1;
    while (scale > directions.completeness[j]) {
      j++;
      }
    float miniscale = (scale - directions.completeness[j - 1])/(directions.completeness[j] - directions.completeness[j - 1]);
    float x = directions.xPoints[j - 1] + (directions.xPoints[j] - directions.xPoints[j - 1])*miniscale;
    float y = directions.yPoints[j - 1] + (directions.yPoints[j] - directions.yPoints[j - 1])*miniscale;
    strokeWeight(5);
    //ellipse(x, y, size, size);
    drawCircle(x, y, statistics[trip.category].fill, false, size);
    strokeWeight(1);
    //println(miniscale + ", " + directions.xPoints[j - 1] + ", " + directions.xPoints[j] + ", " + x + ", " + y);
    //println("point: " + x + ", " + y);
    }
  else {
    //println("no directions for: " + bikeoutStation + " to " + bikeinStation);
    }
  }

Boolean stationIsInImage(int i) {
  return (cabiStations[i].lng >= minLng && cabiStations[i].lng <= maxLng && cabiStations[i].lat >= minLat && cabiStations[i].lat <= maxLat);
  }

Boolean pathMightBeInImage(int i, int j) {
  if (cabiStations[i].lng < minLng && cabiStations[j].lng < minLng) {return false;}
  if (cabiStations[i].lng > maxLng && cabiStations[j].lng > maxLng) {return false;}
  if (cabiStations[i].lat < minLat && cabiStations[j].lat < minLat) {return false;}
  if (cabiStations[i].lat > maxLat && cabiStations[j].lat > maxLat) {return false;}
  return true;  // path might go through viewport
  }
  
void initCurves() { 
  tripControlX = new float[cabiStations.length][cabiStations.length];
  tripControlY = new float[cabiStations.length][cabiStations.length];
  for (int i = 0; i < cabiStations.length; i++) {
    for (int j = 0; j < cabiStations.length; j++) {
      float dx = cabiStations[i].x - cabiStations[j].x;
      float dy = cabiStations[i].y - cabiStations[j].y; 
      float bezierBulge = (float) Math.sqrt(Math.pow(dx, 2) + Math.pow(dy, 2))/16;  // 16 is arbitrary!
      float theta = (float) (Math.atan2(dy, dx) + Math.PI/2);  // shifted 90 degrees 
      tripControlX[i][j] = (cabiStations[i].x + cabiStations[j].x)/2 + bezierBulge*((float) Math.cos(theta));
      tripControlY[i][j] = (cabiStations[i].y + cabiStations[j].y)/2 + bezierBulge*((float) Math.sin(theta)); 
      }
    }
  tripRiders = new int[cabiStations.length][cabiStations.length];
  tripRidersCas = new int[cabiStations.length][cabiStations.length];
  }
  
void drawCircle(float x, float y, color dotColor, boolean blended, int radius) {
  if (radius <= 0)
    return;
  int di = radius*2 - 1; 
  if (blended) {
    // use a more transparent method
    PGraphics tempPage = createGraphics(di, di, JAVA2D);
    tempPage.beginDraw();
    tempPage.background(0);
    tempPage.noStroke();
    tempPage.fill(dotColor);  
    tempPage.ellipse(radius, radius, di, di);
    tempPage.endDraw();
    blend(tempPage, 0, 0, di, di, round(x) - radius, round(y) - radius, di, di, ADD);
    }
  else {
    // draw circles on top of each other
    ellipse(x, y, di, di);
    }
  }

void animate24Hours() {
  final int LAST_FRAME = 24*60*60;  // number of seconds in a 24hr cycle
  int currentUsage;  // number of users currently riding bikes
  int[] maxTraffic = new int[cabiStations.length]; 
  int[] totalTraffic = new int[cabiStations.length];
  for (int i = 0; i < cabiStations.length; i++) {
    maxTraffic[i] = 0;
    totalTraffic[i] = 0;
    }
  // do the math in advance for all possible station pairs
  int frameCount = 0;
  Calendar cal = Calendar.getInstance(); 
  String folder = "frames" + cal.get(Calendar.HOUR) + "-" + cal.get(Calendar.MINUTE) + "/";  
  int imageNo = 0;
  initCurves();  
  println("processing " + validTrips.size() + " trips"); 
  println("============================="); 
  // draw each frame of the animation
  for (int frame = 0; frame <= LAST_FRAME; frame += secondsPerFrame) {
    // initialize counts to zero
    for (int i = 0; i < statistics.length; i++) {
      statistics[i].count = 0;
      } 
    for (int i = 0; i < cabiStations.length; i++) {
      for (int j = 0; j < cabiStations.length; j++) {
        tripRiders[i][j] = 0; 
        tripRidersCas[i][j] = 0;
        } 
      }
    // count riders for each station-pair
    CaBiTrip trip;
    for (int t = 0; t < validTrips.size(); t++) {  
      trip = validTrips.get(t);
      if (frame >= trip.bikeoutTime && frame <= trip.bikeinTime || trip.acrossMidnight && frame <= trip.bikeinTime - SECONDSperDAY) {
        cabiStations[trip.bikeinStation].inUse = true;
        cabiStations[trip.bikeoutStation].inUse = true; 
        }
      }
    // begin drawing frame
    background(bg);
    findBusiestRoutes();
    drawRoutes();  // draw bezier curves
    //println("frame: " + frame);
    drawRiders(frame);  // hmmm, wrong order?
    drawStations(0);  // draw stations 
    int xxx=0;
    for (int i = 0; i < cabiStations.length; i++) {
      for (int j = 0; j < cabiStations.length; j++) {
        if (tripRiders[i][j] > 0) {xxx++;}  
        } 
      }
    //println("xxx: " +xxx);
    if (floor((float)histogramWidth*frame/LAST_FRAME) >= tickCount && tickCount < histogramWidth - 1) { 
      // add a column to the histogram 
      for (int i = 0; i < statistics.length; i++) {
        statistics[i].histogram[tickCount] = statistics[i].count; 
        } 
      tickCount++;  
      //println(100*frame/LAST_FRAME + "%"); 
      } 
    frameCount++;
    drawKey(toHHMM(frame)); 
    saveFrame(folder + "image-" + nf(imageNo++, 5) + ".png");  
    for (int i = 0; i < cabiStations.length; i++) {
      currentUsage = 0;
      for (int j = 0; j < cabiStations.length; j++) {
        currentUsage += tripRiders[i][j] + tripRidersCas[i][j];
        }
      totalTraffic[i] += currentUsage;
      maxTraffic[i] = max(maxTraffic[i], currentUsage);
      }
    } 
  /*
  for (int i = 0; i < cabiStations.length; i++)  
    if (totalTraffic[i] > 0 && totalTraffic[i]/imageNo > 0)
      println(maxTraffic[i]/(totalTraffic[i]/imageNo) + " (" + maxTraffic[i] + " / " + (totalTraffic[i]/imageNo) + ") " + stopName[i]);
  */
  println("maxBusiest = " + maxBusiest);
  println("maxRidersPerRoute = " + maxRidersPerRoute);
  }
   
void animateComparison() { 
  Calendar currentDate = new GregorianCalendar(2015,6,10);
  Calendar maxDate = (Calendar) currentDate.clone();   
  maxDate.add(Calendar.DATE, 7);
  Calendar nextDate = (Calendar) currentDate.clone();   
  println("Date range: " + currentDate.getTime() + " to " + maxDate.getTime()); 
  println("Date range: " + currentDate.getTime() + " to " + maxDate.getTime()); 
  // do the math in advance for all possible station pairs
  int frameCount = 0;
  Calendar cal = Calendar.getInstance(); 
  String folder = "frames" + cal.get(Calendar.HOUR) + "-" + cal.get(Calendar.MINUTE) + "/";  
  int imageNo = 0;
  initCurves();
  println("processing " + validTrips.size() + " trips"); 
  long startInMillis = minDate.getTimeInMillis();
  long timespan = maxDate.getTimeInMillis() - startInMillis;
  long secondsBetween = floor(timespan/1000);
  println("secondsBetween = "+ secondsBetween); 
  long millisPerFrame = secondsPerFrame*1000; 
  int frames = (int)(secondsBetween/secondsPerFrame) + 1;
  balances = new int[cabiStations.length][frames]; 
  balanceSum = new int[cabiStations.length]; 
  for (int i = 0; i < cabiStations.length; i++) {
    for (int j = 0; j < frames; j++)
      balances[i][j] = 0;
    balanceSum[i] = 0;
    }
  CaBiTrip trip; 
  for (int t = 0; t < validTrips.size(); t++) { 
    trip = validTrips.get(t);
    balances[trip.bikeoutStation][floor((trip.bikeoutDayTime.getTimeInMillis() - startInMillis)/millisPerFrame)]--; 
    balances[trip.bikeinStation][floor((trip.bikeinDayTime.getTimeInMillis() - startInMillis)/millisPerFrame)]++; 
    }
  println("============================="); 
  int regRiders;
  int casRiders;
  tripRiders = new int[cabiStations.length][cabiStations.length];
  tripRidersCas = new int[cabiStations.length][cabiStations.length];
  //
  // draw each frame of the animation
  //
  noStroke();
  int radius;
  color fillColor;
  for (int f = 0; f < frames; f++) {
    regRiders = 0; casRiders = 0; 
    // initialize station-pair count to zero
    for (int i = 0; i < cabiStations.length; i++) {
      for (int j = 0; j < cabiStations.length; j++) {
        tripRiders[i][j] = 0;
        tripRidersCas[i][j] = 0;
        }
      cabiStations[i].inUse = false;
      }
    // count riders for each station-pair 
    for (int t = 0; t < validTrips.size(); t++) { 
      trip = validTrips.get(t);
      if (!currentDate.after(trip.bikeinDayTime) && nextDate.after(trip.bikeoutDayTime)) {  /// oh #%$@!
        if (trip.isRegistered) {
          tripRiders[trip.bikeoutStation][trip.bikeinStation]++;
          regRiders++;
          }
        else {
          tripRidersCas[trip.bikeoutStation][trip.bikeinStation]++;
          casRiders++;
          }  
        cabiStations[trip.bikeinStation].inUse = true;
        cabiStations[trip.bikeoutStation].inUse = true;
        }
      }
    background(bg);
    drawStations(f); 
    //drawKey(minDate.getTime().toString()); 
    currentDate.add(Calendar.SECOND, secondsPerFrame);
    nextDate.add(Calendar.SECOND, secondsPerFrame);
    frameCount++; 
    saveFrame(folder + "image-" + nf(imageNo++, 5) + ".png"); 
    if (f % 16 == 0)   
      println(100*f/frames + "%"); 
    } 
  }   

void animateStartToFinish() {    
  Calendar currentDate = new GregorianCalendar(minDate.get(Calendar.YEAR), minDate.get(Calendar.MONTH), minDate.get(Calendar.DAY_OF_MONTH), minDate.get(Calendar.HOUR_OF_DAY), 0, 0);
  Calendar nextDate = (Calendar) currentDate.clone();   // screwed up???
  println("Date range: " + currentDate.getTime() + " to " + maxDate.getTime()); 
  // do the math in advance for all possible station pairs
  int frameCount = 0;
  Calendar cal = Calendar.getInstance(); 
  String folder = "frames" + cal.get(Calendar.HOUR) + "-" + cal.get(Calendar.MINUTE) + "/";  
  int imageNo = 0;
  initCurves();
  println("processing " + validTrips.size() + " trips"); 
  long startInMillis = minDate.getTimeInMillis();
  long timespan = maxDate.getTimeInMillis() - startInMillis;
  long secondsBetween = floor(timespan/1000);
  println("secondsBetween = "+ secondsBetween); 
  long millisPerFrame = secondsPerFrame*1000; 
  int frames = (int)(secondsBetween/secondsPerFrame) + 1;
  balances = new int[cabiStations.length][frames]; 
  balanceSum = new int[cabiStations.length]; 
  for (int i = 0; i < cabiStations.length; i++) {
    for (int j = 0; j < frames; j++)
      balances[i][j] = 0;
    balanceSum[i] = 0;
    }
  CaBiTrip trip; 
  for (int t = 0; t < validTrips.size(); t++) { 
    trip = validTrips.get(t);
    int slotOut = floor((trip.bikeoutDayTime.getTimeInMillis() - startInMillis)/millisPerFrame);
    int slotIn = floor((trip.bikeinDayTime.getTimeInMillis() - startInMillis)/millisPerFrame);
    //println(slotOut + "/" + slotIn + ", " + frames);
    balances[trip.bikeoutStation][slotOut]--; 
    balances[trip.bikeinStation][slotIn]++; 
    }
  println("============================="); 
  int regRiders;
  int casRiders;
  tripRiders = new int[cabiStations.length][cabiStations.length];
  tripRidersCas = new int[cabiStations.length][cabiStations.length];
  //
  // draw each frame of the animation
  //
  noStroke();
  int radius;
  color fillColor;
  for (int f = 0; f < frames; f++) {
    regRiders = 0; casRiders = 0; 
    // initialize station-pair count to zero
    for (int i = 0; i < cabiStations.length; i++) {
      for (int j = 0; j < cabiStations.length; j++) {
        tripRiders[i][j] = 0; 
        tripRidersCas[i][j] = 0;
        }
      cabiStations[i].inUse = false;
      }
    // count riders for each station-pair 
    for (int t = 0; t < validTrips.size(); t++) { 
      trip = validTrips.get(t);
      if (!currentDate.after(trip.bikeinDayTime) && nextDate.after(trip.bikeoutDayTime)) {  /// oh #%$@!
        if (trip.isRegistered) {
          tripRiders[trip.bikeoutStation][trip.bikeinStation]++;
          regRiders++;
          }
        else {
          tripRidersCas[trip.bikeoutStation][trip.bikeinStation]++;
          casRiders++;
          }
        cabiStations[trip.bikeinStation].inUse = true;
        cabiStations[trip.bikeoutStation].inUse = true; 
        }
      }
    background(bg);
    drawStations(f); 
    drawKey(minDate.getTime().toString()); 
    currentDate.add(Calendar.SECOND, secondsPerFrame);
    nextDate.add(Calendar.SECOND, secondsPerFrame);
    frameCount++; 
    saveFrame(folder + "image-" + nf(imageNo++, 5) + ".png"); 
    if (f % 16 == 0)   
      println(100*f/frames + "%"); 
    } 
  }

void animateSweepingPeriod() {  
  int frameCount = 0;
  println("SWEEPING!");
  Calendar currentDate = new GregorianCalendar(minDate.get(Calendar.YEAR), minDate.get(Calendar.MONTH), minDate.get(Calendar.DAY_OF_MONTH), minDate.get(Calendar.HOUR_OF_DAY), 0, 0);
  Calendar nextDate = (Calendar) currentDate.clone(); 
  nextDate.add(Calendar.DATE, 7);
  println("Date range: " + currentDate.getTime() + " to " + maxDate.getTime()); 
  // do the math in advance for all possible station pairs 
  Calendar cal = Calendar.getInstance(); 
  String folder = "frames" + cal.get(Calendar.HOUR) + "-" + cal.get(Calendar.MINUTE) + "/";  
  int imageNo = 0; 
  for (int i = 0; i < cabiStations.length; i++) { 
    cabiStations[i].inUse = true;
    }  
  println("processing " + validTrips.size() + " trips"); 
  long startInMillis = minDate.getTimeInMillis();
  long timespan = maxDate.getTimeInMillis() - startInMillis;
  long minutesBetween = floor(timespan/60000);
  println("minutesBetween = "+ minutesBetween);
  long minutesPerFrame = 120*60;
  long millisPerFrame = minutesPerFrame*60000;
  int frames = (int)((minutesBetween - 7*24*60)/minutesPerFrame) + 1; 
  CaBiTrip trip;  
  println("============================="); 
  initCurves();
  int regRiders;
  int casRiders;
  tripRiders = new int[cabiStations.length][cabiStations.length];
  tripRidersCas = new int[cabiStations.length][cabiStations.length];
  //
  // draw each frame of the animation
  //
  noStroke();
  SimpleDateFormat formatter = new SimpleDateFormat("MMM d yyyy h:mma");
  int radius;
  color fillColor;
  for (int f = 0; f <= frames; f++) {
    regRiders = 0; casRiders = 0; 
    // initialize station-pair count to zero
    for (int i = 0; i < cabiStations.length; i++) {
      for (int j = 0; j < cabiStations.length; j++) {
        tripRiders[i][j] = 0; 
        tripRidersCas[i][j] = 0;
        } 
      }
    // count riders for each station-pair 
    for (int t = 0; t < validTrips.size(); t++) { 
      trip = validTrips.get(t);
      if (!currentDate.after(trip.bikeinDayTime) && nextDate.after(trip.bikeoutDayTime)) {  /// oh #%$@!
        if (trip.isRegistered) {
          tripRiders[trip.bikeoutStation][trip.bikeinStation]++;
          regRiders++;
          }
        else {
          tripRidersCas[trip.bikeoutStation][trip.bikeinStation]++;
          casRiders++;
          } 
        }
      }
    //println(regRiders, casRiders, currentDate.getTime(), nextDate.getTime());
    background(bg);
    findBusiestRoutes();
    drawRoutes();
    drawStations(0); 
    if (floor((float)histogramWidth*f/frames) >= tickCount && tickCount < histogramWidth - 1) { 
      // add a column to the histogram 
      statistics[0].histogram[tickCount] = casRiders;
      statistics[1].histogram[tickCount] = regRiders;
      tickCount++;  
      println(100*f/frames + "%"); 
      } 
    drawKey(formatter.format(currentDate.getTime()) + " - " + formatter.format(nextDate.getTime())); 
    frameCount++; 
    if (currentDate.after(maxDate))
      println("ERROR: animating past data source");
    saveFrame(folder + "image-" + nf(imageNo++, 5) + ".png"); 
    currentDate.add(Calendar.MINUTE, (int) minutesPerFrame);
    nextDate.add(Calendar.MINUTE, (int) minutesPerFrame);
    } 
  }
  
void countStationsForBike(String bikeNo) {  
  CaBiTrip trip;  
  int[] tripsPerStation = new int[cabiStations.length];
  for (int i = 0; i < tripsPerStation.length; i++) { 
    tripsPerStation[i] = 0;
    }
  for (int t = 0; t < validTrips.size(); t++) { 
    trip = validTrips.get(t);
    if (trip.bikeNo.equals(bikeNo)) {
      tripsPerStation[trip.bikeoutStation]++;
      tripsPerStation[trip.bikeinStation]++;
      } 
    }
  println("==>");
  for (int i = 0; i < tripsPerStation.length; i++) { 
    if (tripsPerStation[i] > 0) {
      print(cabiStations[i].id + ":" + tripsPerStation[i] + ",");
      }
    }
  println("==>");
  }

void animateBikePath(String bikeNo) { 
  int frameCount = 0;
  Calendar cal = Calendar.getInstance(); 
  String folder = "frames" + cal.get(Calendar.HOUR) + "-" + cal.get(Calendar.MINUTE) + "/";  
  int imageNo = 0;  
  long startInMillis = minDate.getTimeInMillis();
  long timespan = maxDate.getTimeInMillis() - startInMillis;
  long minutesBetween = floor(timespan/60000);
  long minutesPerFrame = 120*60;
  long millisPerFrame = minutesPerFrame*60000;
  int frames = (int)((minutesBetween - 7*24*60)/minutesPerFrame) + 1; 
  int radius;
  color fillColor;
  float midx, midy;
  float age;
  color dotColor;
  println("SINGLE BIKE PATH!");
  println("Date range: " + minDate.getTime() + " to " + maxDate.getTime()); 
  // do the math in advance for all possible station pairs 
  println("processing " + validTrips.size() + " trips"); 
  println("minutesBetween = "+ minutesBetween);
  CaBiTrip trip;  
  CaBiTrip mostRecent;  
  Boolean firstTrip = false;
  Boolean noMostRecent = true;
  println("============================="); 
  initCurves();  
  noStroke();
  SimpleDateFormat formatter = new SimpleDateFormat("MMM d yyyy h:mma");
  initCurves();   
  long totalMillisecondsInMovie = maxDate.getTimeInMillis() - minDate.getTimeInMillis();
  long totalFrames = totalMillisecondsInMovie/(secondsPerFrame*1000); 
  Calendar currentDate = new GregorianCalendar(minDate.get(Calendar.YEAR), minDate.get(Calendar.MONTH), minDate.get(Calendar.DAY_OF_MONTH), minDate.get(Calendar.HOUR_OF_DAY), 0, 0);
  Boolean keepgoing = true;
  while (keepgoing) {  // draw a frame
    keepgoing = currentDate.before(maxDate);
    if (imageNo % 20 == 0) println(100*imageNo/totalFrames + "%");
    // initialize station-pair count to zero
    for (int i = 0; i < cabiStations.length; i++) {
      for (int j = 0; j < cabiStations.length; j++) {
        tripRiders[i][j] = 0; 
        } 
      }
    background(bg);  
    noFill();  
    int tripCount = 0;
    noMostRecent = true;
    mostRecent = null;
    for (int t = 0; t < validTrips.size(); t++) { 
      trip = validTrips.get(t);
      if (trip.bikeNo.equals(bikeNo) && currentDate.after(trip.bikeoutDayTime)) {  // trip in the past or present
        tripCount++;
        if (mostRecent == null || trip.bikeoutDayTime.after(mostRecent.bikeoutDayTime)) {
          mostRecent = trip;
          noMostRecent = false;
          }
        Boolean isRegistered = trip.isRegistered;
        midx = tripControlX[trip.bikeoutStation][trip.bikeinStation];
        midy = tripControlY[trip.bikeoutStation][trip.bikeinStation];
        tripRiders[trip.bikeoutStation][trip.bikeinStation]++;
        age = 1 - (trip.bikeoutDayTime.getTimeInMillis() - minDate.getTimeInMillis())/totalMillisecondsInMovie;  // 0 to 1
        stroke(color(241, 89, 42, 0.25 + 0.75*age)); 
        strokeWeight(3*tripRiders[trip.bikeoutStation][trip.bikeinStation]); 
      stroke(255, 255, 0, 64);
      strokeWeight(3*tripRiders[trip.bikeoutStation][trip.bikeinStation]);
        //  println("[" + trip.bikeoutStation + "][" + trip.bikeinStation + "] = " + tripRiders[trip.bikeoutStation][trip.bikeinStation]);
        bezier(cabiStations[trip.bikeoutStation].x, cabiStations[trip.bikeoutStation].y, midx,midy,midx,midy, cabiStations[trip.bikeinStation].x, cabiStations[trip.bikeinStation].y); 
        cabiStations[trip.bikeinStation].inUse = true;
        cabiStations[trip.bikeoutStation].inUse = true;  
        if (false && currentDate.before(trip.bikeinDayTime)) {  // trip in the present
          float scale = (currentDate.getTimeInMillis() -  trip.bikeoutDayTime.getTimeInMillis())/(trip.bikeinDayTime.getTimeInMillis() -  trip.bikeoutDayTime.getTimeInMillis()) ;  
          stroke(255, 0, 0);
          strokeWeight(1);
          drawPointAlongPath(trip, scale, 15);
          mostRecent = null;
          }
        } 
      }
    drawKey(formatter.format(currentDate.getTime()));  
    if (mostRecent != null) {
      stroke(255, 0, 0);
      strokeWeight(1);
      fill(255, 255, 0);
      ellipse(cabiStations[mostRecent.bikeinStation].x, cabiStations[mostRecent.bikeinStation].y, 15, 15);
      }
    textAlign(RIGHT); 
    textSize(18);
    String plural = "s";
    if (tripCount == 1) plural = " ";
    strokeText(tripCount + " trip" + plural, swidth - 14, sheight - 14); 
    drawStations(0);   
    frameCount++;  
    saveFrame(folder + "image-" + nf(imageNo++, 5) + ".png"); 
    currentDate.add(Calendar.SECOND, secondsPerFrame);
    } 
  } 
    
String IDof(String name) { 
  name = name.substring(1, name.length() - 1);
  String[] metroName = {"McLean","Tysons Corner","Greensboro","Spring Hill","Wiehle","Navy Yard","Judiciary Square","McPherson Square","Metro Center","Mt. Vernon Square-UDC","U Street-Cardozo","Shaw-Howard University","Union Station","Congress Heights","Anacostia","Southern Avenue","Eastern Market","Stadium-Armory","Minnesota Avenue","Van Ness-UDC","Cleveland Park","Columbia Heights","Georgia Avenue-Petworth","Forest Glen","Wheaton","Silver Spring","Fort Totten","Prince George's Plaza","Branch Avenue","Benning Road","Capitol Heights","Deanwood","Cheverly","Addison Road","College Park-U of MD","Landover","Glenmont","Largo Town Center","Morgan Blvd.","New York Ave","Huntington","Court House","Twinbrook","Farragut North","Naylor Road","Suitland","Franconia-Springfield","Vienna","Dunn Loring","West Falls Church","East Falls Church","Van Dorn Street","Eisenhower Avenue","Virginia Square-GMU","Rosslyn","Tenleytown-AU","Friendship Heights","Bethesda","Grosvenor","White Flint","Medical Center","Shady Grove","King Street","Pentagon City","Crystal City","Reagan Washington National Airport","Pentagon","Arlington Cemetery","Foggy Bottom","Dupont Circle","Woodley Park-Zoo","L'Enfant Plaza","Federal Triangle","Archives-Navy Memorial","Waterfront","Gallery Place-Chinatown","Rhode Island Avenue","West Hyattsville","Greenbelt","Capitol South","Ballston","Rockville","Farragut West","Federal Center SW","Potomac Avenue","Brookland","New Carrollton","Takoma","Clarendon","Braddock Road","Smithsonian"};
  String[] metroID = {"N01","N02","N03","N04","N06","F05","B02","C02","A01","E01","E03","E02","B03","F07","F06","F08","D06","D08","D09","A06","A05","E04","E05","B09","B10","B08","B06","E08","F11","G01","G02","D10","D11","G03","E09","D12","B11","G05","G04","B35","C15","K01","A13","A02","F09","F10","J03","K08","K07","K06","K05","J02","C14","K03","C05","A07","A08","A09","A11","A12","A10","A15","C13","C08","C09","C10","C07","C06","C04","A03","A04","D03","D01","F02","F04","B01","B04","E07","E10","D05","K04","A14","C03","D04","D07","B05","D13","B07","K02","C12","D02"};
  int t = 0;
  do { 
    if (metroName[t].equals(name))  
      break; 
    t++;
    } while (t < metroName.length);
  if (t >= metroName.length)
    println("ERROR: " + name);
  return metroID[t]; 
  }

void convert() {  
  PrintWriter output;
  output = createWriter("data.txt"); 
  String lines[] = loadStrings("/Users/michael/mvjantzen.com/metro/data/2014-October-OD-Quarter-Hour.csv");
  for (int t = 1; t < lines.length; t++) {  // skip 1st line
    String[] cols = split(lines[t], ",");
    output.println(cols[3] + "," + IDof(cols[4]) + "," + IDof(cols[5]) + "," + cols[0]);
    }
  output.flush();
  output.close();
  }

void setup() {
  //convert();
  initSystem("cabi.csv");
  histogramWidth = 192;
  validTrips = new ArrayList<CaBiTrip>(3200000);  // guess number of records
  displayMethod = RIDERTYPE;  // choose BIKEPATH or CHARCOAL or RIDERTYPE or BALANCES or SWEEP
  // if displayMethod == RIDERTYPE, choose a value for rideTypes:
  rideTypes = JURISDICTION;  // CLUSTER, CASUAL_REGISTERED, WEEKDAY_WEEKEND, JURISDICTION, BIKENO, TRIPDAY, ALL_TYPES
  if (displayMethod == RIDERTYPE) { 
    if (rideTypes == CLUSTER) {
      statistics = new statKey[3]; 
      statistics[0] = new statKey("entering", color(109, 197,  58, 204), color(109, 197,  58, 153));  // green
      statistics[1] = new statKey("within",   color(246,  93,  85, 204), color(246,  93,  85, 153));  // red
      statistics[2] = new statKey("leaving",  color(  8, 170, 245, 204), color  (8, 170, 245, 153));  // blue
      } 
    else if (rideTypes == CASUAL_REGISTERED) {
      statistics = new statKey[2]; 
      statistics[0] = new statKey("casual", color(252, 48, 29), color(252, 48, 29, 50));  // CaBi red
      statistics[1] = new statKey("registered", color(254,204,47), color(254,204,47, 50));  // CaBi yellow
      } 
    else if (rideTypes == WEEKDAY_WEEKEND) {
      statistics = new statKey[2]; 
      statistics[0] = new statKey("weekend", color(64,255,128), color(64,255,128, 50));  // green
      statistics[1] = new statKey("weekday", color(128,64,255), color(128,64,255, 50));  // purple
      } 
    else if (rideTypes == JURISDICTION) {
      statistics = new statKey[5]; 
      statistics[0] = new statKey("DC",         color(255, 98, 82, 153), color(255, 98, 82, 102));  // orange
      statistics[1] = new statKey("Arlington",  color(232,183, 63, 153), color(232,183, 63, 102));  // mustard
      statistics[2] = new statKey("Alexandria", color(132,255, 54, 153), color(132,255, 54, 102));  // green
      statistics[3] = new statKey("Maryland",   color( 69,215,255, 153), color( 69,215,255, 102));  // blue
      statistics[4] = new statKey("Fairfax",    color(255, 69,252, 153), color(255, 69,252, 102));  // purple
      } 
    else if (rideTypes == BIKENO) {
      statistics = new statKey[2]; 
      statistics[0] = new statKey("Busybike",    color(252, 48, 29,204), color(252, 48, 29,153));  // red
      statistics[1] = new statKey("Other bikes", color(252,252,252, 51), color(252,252,252, 26));  // grey
      } 
    else if (rideTypes == TRIPDAY) {
      showKeyCalculation = true;
      statistics = new statKey[2]; 
      statistics[0] = new statKey("March 9", color(108,204,26, 153), color(108,204,26, 51));  // green
      statistics[1] = new statKey("March 16",  color(255, 244, 7,153), color(255, 244, 7,51));  // yellow
      } 
    else if (rideTypes == ALL_TYPES) {
      statistics = new statKey[13];
      statistics[0] = new statKey("24-hour", color(255,203,10, 204), color(255,203,10, 26));
      statistics[1] = new statKey("3-Day", color(232,133,9, 204), color(232,133,9, 26));
      statistics[2] = new statKey("30-day", color(255,63,3, 204), color(255,63,3, 26));
      statistics[3] = new statKey("Annual",    color(232, 9, 72,204), color(232, 9, 72,153));
      statistics[4] = new statKey("Annual - Silver", color(204,6,255, 204), color(204,6,255, 26));
      statistics[5] = new statKey("Corporate", color(130,3,255, 204), color(130,3,255, 26));
      statistics[6] = new statKey("Arlington", color(8,3,232, 204), color(8,3,232, 26));
      statistics[7] = new statKey("Arlington Monthly", color(10,118,255, 204), color(10,118,255, 26));
      statistics[8] = new statKey("Day Key $7", color(3,211,232, 204), color(3,211,232, 26));
      statistics[9] = new statKey("Day Key $10", color(14,255,158, 204), color(14,255,158, 26));
      statistics[10] = new statKey("MCLiberty", color(88,255,0, 204), color(88,255,0, 26));
      statistics[11] = new statKey("Employee", color(192,232,12, 204), color(192,232,12, 26));
      statistics[12] = new statKey("Job Access", color(255,233,0, 204), color(255,233,0, 26));
      }
    else {
      println("ERROR: unexpected rideTypes values");
      }
    for (int i = 0; i < statistics.length; i++) {
      statistics[i].histogram = new int[histogramWidth];
      }
    }
  else {
    statistics = new statKey[0];  // no stats will be shown
    }
  secondsPerFrame = 240;  // 60 or 240 or whatever
  // Pick the background image and set the lat/lng boundaries:
  // to use a picture you must know the lat/lng boundaries.
  // this section saves that information; comment out the ones not being used
  // order is S:bottom, W:left, N:top, E:right, width, height
  setBoundary("arlington-dc-600x400.png", 38.8299, -77.1335, 38.9099, -76.9791, 600, 450, all(), "Capital Bikeshare");
  setBoundary("cabionthemall.png", 38.8730, -77.0557, 38.8997, -77.0043, 600, 450, all(), "Capital Bikeshare");
  setBoundary("rosslyn640x480.png", 38.8895, -77.0841, 38.9055, -77.0567, 640, 480, rosslyn(), "Rosslyn (Arlington, VA)");
  setBoundary("nwrectangle600x450.png", 38.8862, -77.0533, 38.9012, -77.0275, 600, 450, all(), "Capital Bikeshare");
  setBoundary("greatercrystalcity600x450.png", 38.8390, -77.0805, 38.8689, -77.0291, 600, 450, all(), "Capital Bikeshare");
  setBoundary("caohillne680x510.png", 38.8893, -77.0214, 38.9063, -76.9922, 680, 510, centerForTotalHealth(), "Kaiser Permanente Center for Total Health"); 
  setBoundary("dc-va-600x450.jpg", 38.7990, -77.1604, 38.9591, -76.8861, 600, 450, all(), "Capital Bikeshare");   
  setBoundary("shaw640x480.png", 38.9050, -77.0357, 38.9210, -77.0082, 640, 480, all(), "Wonder Bread Factory"); 
  setBoundary("dc-cc450x600.png", 38.8318, -77.0861, 38.9119, -77.0090, 450, 600, all(), "Capital Bikeshare"); 
  setBoundary("dc-core800x600.png", 38.8404, -77.1031, 38.9204, -76.9659, 800, 600, all(), "Capital Bikeshare"); 
  setBoundary("crystalcity480x320.png", 38.8369, -77.0904, 38.8795, -77.0082, 480, 320, greaterCrystalCity(), "Crystal City"); 
  setBoundary("lincoln640x480.png", 38.8750, -77.0725, 38.9070, -77.0177, 640, 480, lincoln(), "Lincoln Memorial"); 
  setBoundary("jeffersonmemorial640x480.png", 38.8644, -77.0719, 38.8964, -77.0171, 640, 480, jefferson(), "Jefferson Memorial"); 
  setBoundary("gallaudet640x480.png", 38.8953, -77.0096, 38.9113, -76.9821, 640, 480, gallaudet(), "Gallaudet");
  setBoundary("washington440x660.png", 38.7851, -77.2243, 39.1370, -76.9228, 440, 660, all(), "Capital Bikeshare");
  setBoundary("clarendon660x440.png", 38.8795, -77.1086, 38.8941, -77.0803, 660, 440, gmu(), "GMU Founders Hall");
  setBoundary("gallaudet440x660.png", 38.8893, -77.0058, 38.9113, -76.9870, 440, 660, gallaudet(), "Gallaudet");
  setBoundary("gallaudet800x600dark.png", 38.8799, -77.0448, 38.9200, -76.9762, 800, 600, gallaudet(), "Gallaudet");
  setBoundary("crystalcity640x480dark.png", 38.8388, -77.0742, 38.8708, -77.0193, 640, 480, crystalCityMetro(), "Crystal City");
  setBoundary("crystalcity800x600dark.png", 38.8412, -77.0875, 38.8813, -77.0190, 800, 600, crystalCityMetro(), "Crystal City");
  setBoundary("crystalcity480x320.png", 38.8369, -77.0904, 38.8795, -77.0082, 480, 320, greaterCrystalCity(), "Crystal City");
  setBoundary("arlingtonarea1020x680.png", 38.8578, -77.1241, 38.9032, -77.0366, 1020, 680, all(), "Capital Bikeshare");
  setBoundary("mall1400x700dark.png", 38.8788, -77.0611, 38.9021, -77.0011, 1400, 700, all(), "Capital Bikeshare");
  setBoundary("kpcth1000x750dark.png", 38.8827, -77.0305, 38.9078, -76.9876, 1000, 750, all(), "Capital Bikeshare");
  setBoundary("arlingtonarea600x450.png", 38.8047, -77.1436, 38.9247, -76.9379, 600, 450, dupont(), "Capital Bikeshare");
  setBoundary("walterreed960x640.png", 38.8547, -77.1183, 38.8974, -77.0360, 960, 640, dupont(), "S Walter Reed Dr & 8th St S");
  setBoundary("lincoln400x300dark.png", 38.8716, -77.0725, 38.9116, -77.0039, 400, 300, all(), "Lincoln Memorial");
  setBoundary("dc400x300dark.png", 38.8360, -77.1717, 38.9960, -76.8974, 400, 300, all(), "Capital Bikeshare");
  setBoundary("dc800x600dark.png", 38.8360, -77.1717, 38.9960, -76.8974, 800, 600, all(), "Capital Bikeshare");
  setBoundary("unionstation800x600dark.png", 38.8733, -77.0512, 38.9133, -76.9826, 800, 600, unionstation(), "Union Station");
  setBoundary("lincoln800x600dark.png", 38.8716, -77.0725, 38.9116, -77.0039, 800, 600, lincoln(), "Lincoln Memorial");
  setBoundary("dupont800x600dark.png", 38.8836, -77.0720, 38.9236, -77.0034, 800, 600, dupont(), "Dupont Circle");
  setBoundary("dc-core800x600dark.png", 38.8469, -77.1031, 38.9270, -76.9659, 800, 600, all(), "Capital Bikeshare"); 
  setBoundary("unionstation800x600dark.png", 38.8733, -77.0512, 38.9133, -76.9826, 800, 600, unionstation(), "Union Station");
  setBoundary("dc800x600dark.png", 38.8360, -77.1717, 38.9960, -76.8974, 800, 600, all(), "Capital Bikeshare");
  setBoundary("dc800x600zoomblack.png", 38.8741, -77.0740, 38.9181, -76.9984, 800, 600, all(), "Capital Bikeshare");
  setBoundary("arlington-dc-600x400.png", 38.8299, -77.1335, 38.9099, -76.9791, 600, 400, all(), "Capital Bikeshare");
  setBoundary("crystalcity800x600dark.png", 38.8412, -77.0875, 38.8813, -77.0190, 800, 600, all(), "Crystal City");
  setBoundary("nova600x800dark.png", 38.79148, -77.12660, 38.907253, -77.01558, 600, 800, all(), "Northern Virginia");
  setBoundary("region500x750dark.png", 38.78513, -77.23099, 39.18557, -76.88698, 500, 750, all(), "Capital Bikeshare");
  setBoundary("arlington600x800dark.png", 38.82716, -77.12663, 38.90723, -76.98892, 800, 600, arlington(), "Capital Bikeshare");
  setBoundary("dc800x600midzoomblack.png", 38.85108, -77.10229, 38.93130, -76.96508, 800, 600, all(), "Capital Bikeshare");
  setBoundary("region640x640dark.png", 38.78854, -77.27364, 39.12946, -76.83205, 640, 640, all(), "Capital Bikeshare");
  setBoundary("lowerregion640x480dark.png", 38.76640, -77.27589, 39.02452, -76.83712, 640, 480, all(), "Capital Bikeshare"); 
  setBoundary("dc800x600black.png", 38.8071, -77.1968, 38.9750, -76.9094, 800, 600, all(), "Capital Bikeshare");
  setBoundary("lowercloseup640x480dark.png", 38.79584, -77.22611, 39.00131, -76.87523, 640, 480, all(), "Capital Bikeshare");  
  lightmap = false;
  initDirections(); 
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2015-Q1-Trips-History-Data.csv");
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2015-Q2-Trips-History-Data.csv");
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2015-Q3-cabi-trip-history-data.csv"); 
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2015-Q4-Trips-History-Data.csv");
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2016-Q1-Trips-History-Data.csv"); 
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2016-Q2-Trips-History-Data.csv"); 
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/2016-Q3-Trips-History-Data-1.csv"); 
  setDatasource("/Users/michael/mvjantzen.com/cabi/data/2016-Q3-Trips-History-Data-2.csv"); 
  //setDatasource("/Users/michael/mvjantzen.com/cabi/data/REIweekend.csv"); 
  // String csvFile, int outStation, int inStation, int outTime, int inTime, int reg, int idNo
  dataTitle = "Bike W21852 in 2015"; 
  dataTitle = "All trips in 2015"; 
  dataTitle = "Jan - Sep, 2016";
  println("Date range: " + minDate.getTime() + " to " + maxDate.getTime());
  //getStats();
  //if (2==4/0) 
  size(swidth, sheight, JAVA2D);
  println("=============================");
  if (displayMethod == SWEEP) {
    subTitle = "Trips per Week";
    animateSweepingPeriod();
    }
  else if (displayMethod == BALANCES) {
    subTitle = "Balances";
    animateStartToFinish();
    }
  else if (displayMethod == BIKEPATH) {
    subTitle = "Bike Path";
    //countStationsForBike("W21852");
    animateBikePath("W21852");
    }
  else {
    subTitle = "24-hour cycle";
    //animateComparison(); 
    animate24Hours();
    }
  println("done!");
  }

void draw() {   
  }
