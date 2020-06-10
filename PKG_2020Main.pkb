CREATE OR REPLACE PACKAGE BODY PKG_2020Main AS

/* FORWARD DECLERATIONS */
PROCEDURE GENERATE_FORECAST (p_date IN DATE DEFAULT SYSDATE);



PROCEDURE RM16_FORECAST (p_date IN DATE DEFAULT SYSDATE) is
BEGIN
    GENERATE_FORECAST(p_date);   
END;

/* PRIVATE PROCEDURES AND FUNCIONS */

/*
    This module print out the message to both the log table and
    to the script output.
*/

PROCEDURE MESSAGE_LOG (P_MESSAGE IN VARCHAR2)
IS

BEGIN
--
    COMMON.LOG(P_MESSAGE);
    DBMS_OUTPUT.PUT_LINE(P_MESSAGE);
--
EXCEPTION 
    WHEN NO_DATA_FOUND THEN
        MESSAGE_LOG('No Data Found: '||SQLERRM);
END;

-----------------------------------------------------------------

/*
    This module check if the prediction date is a holiday by 
    comparing the p_date with the records in DBP_HOLIDAY.
*/

FUNCTION CHECK_HOLIDAY(p_date IN DATE default sysdate) 
RETURN BOOLEAN IS 

V_ROWS_FOUND NUMBER;

BEGIN
--
    SELECT COUNT(*)
    INTO V_ROWS_FOUND
    FROM DBP_HOLIDAY
    WHERE TRUNC(HOLIDAY_DATE) = TRUNC(p_date);

        IF V_ROWS_FOUND = 1 THEN 
            RETURN TRUE;
        ELSE 
            RETURN FALSE;
        END IF;
--
EXCEPTION
    WHEN OTHERS THEN    
    MESSAGE_LOG('Error is' || SQLERRM);
END;

-----------------------------------------------------------------

FUNCTION CHECK_HOLIDAY_RECORD 
RETURN BOOLEAN IS 

/*
    This module check if there are previous records of holiday 
    electricity consumption in V_NEM_ABERAGE.
*/

V_ROWS_FOUND NUMBER;
--
BEGIN 
    SELECT COUNT(*)
    INTO V_ROWS_FOUND
    FROM V_NEM_AVERAGE
    WHERE DAY_NAME = 'Holiday';

        IF V_ROWS_FOUND = 1 THEN 
            RETURN TRUE;
        ELSE 
            RETURN FALSE;
        END IF;
--
EXCEPTION
    WHEN OTHERS THEN    
    MESSAGE_LOG('Error is' || SQLERRM);
END;

-----------------------------------------------------------------

/*
    This module check if there are previous records in LOCAL_RM16 
*/

FUNCTION CHECK_ROWS(p_date IN DATE)
RETURN BOOLEAN
IS

V_ROWS_FOUND NUMBER;
BEGIN
--
    SELECT COUNT(*)
    INTO V_ROWS_FOUND
    FROM LOCAL_RM16
    WHERE TRUNC(LOCAL_RM16.DAY) >= TRUNC(p_date);

    IF V_ROWS_FOUND >=1 THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        MESSAGE_LOG('Error: '|| SQLERRM);
END;

-----------------------------------------------------------------

/*
    This module return values from DBP_PARAMETER to avoid hard coding 
*/

FUNCTION GET_PARAM(p_category VARCHAR2, p_code VARCHAR)
RETURN VARCHAR2 IS 

v_value VARCHAR2(35);

BEGIN
--
 SELECT VALUE INTO v_value
 FROM DBP_PARAMETER
 WHERE CATEGORY = p_category
 AND code =p_code;
--
 RETURN v_value;
 
 EXCEPTION
 WHEN OTHERS THEN
    MESSAGE_LOG('Error occurred with get_param' || p_category || ' ' || p_code);
    MESSAGE_LOG('Error is' || SQLERRM || 'and code is ' || SQLCODE);
END;

-----------------------------------------------------------------

/*
    This module generate the forecast based on past consumption 
    for 14 days every half hour intervals. 
*/

PROCEDURE GENERATE_FORECAST (p_date IN DATE DEFAULT SYSDATE)
IS

--
v_start_date DATE := TRUNC(p_date + 1); --FORECASTING WILL START FROM MIDNIGHT
v_day DATE;
v_avg_value FLOAT;
v_is_holiday BOOLEAN;
v_holiday_record BOOLEAN;
v_runlogrecord RUN_TABLE%ROWTYPE;
v_runLogID NUMBER;
moduleRan EXCEPTION;
c_runBuffer CONSTANT NUMBER := GET_PARAM('BUFFER_NUMBER','RUN_BUFFER'); -- set a constant to check last run (1/24 is to check last hour)
c_moduleName CONSTANT VARCHAR(20) := GET_PARAM('RUN_TABLE', 'MODULE_NAME');

BEGIN

    BEGIN
        SELECT * INTO v_runlogrecord
        FROM RUN_TABLE
        WHERE 1 =1
        AND UPPER(MODULE_NAME) = c_moduleName
        AND outcome = 'SUCCESS'
        AND (RUN_END > (sysdate - c_runBuffer) OR RUN_END is null);

        RAISE moduleRan; -- if there is a record found, raise moduleRan exception 

        EXCEPTION 
            WHEN NO_DATA_FOUND THEN 
            SELECT seq_runID.NEXTVAL INTO v_runLogID from dual; -- get the sequence 

            INSERT INTO RUN_TABLE(RUN_ID, RUN_START, RUN_END, OUTCOME, REMARKS, MODULE_NAME)
            VALUES(v_runLogID, sysdate, NULL, NULL, 'Start Program', c_moduleName);
        END;

V_DAY:= V_START_DATE;

FOR forecast IN 1..14
LOOP 
    V_IS_HOLIDAY := CHECK_HOLIDAY(V_DAY);
    V_HOLIDAY_RECORD := CHECK_HOLIDAY_RECORD;
    
    IF V_IS_HOLIDAY AND  V_HOLIDAY_RECORD THEN
        INSERT INTO LOCAL_RM16 (COMPANY_CODE, SETTLEMENT_CASE_ID,SETTLEMENT_RUN_ID, STATEMENT_TYPE, TNI, METERTYPE, FRMP, LR, MDP, CHANGE_DATE, DAY,TRANSACTION_ID, HH, VOLUME)
        SELECT null, null, null, 'FORECAST', TNI, null, FRMP, LR, null, sysdate, v_day, null, HH, AVERAGE_VOLUME 
        FROM v_nem_average 
        WHERE day_name LIKE 'Holiday';
        
    ELSIF V_IS_HOLIDAY THEN
        INSERT INTO LOCAL_RM16 (COMPANY_CODE, SETTLEMENT_CASE_ID,SETTLEMENT_RUN_ID, STATEMENT_TYPE, TNI, METERTYPE, FRMP, LR, MDP, CHANGE_DATE, DAY,TRANSACTION_ID, HH, VOLUME)
        SELECT null, null, null, 'FORECAST', TNI, null, FRMP, LR, null, sysdate, v_day, null, HH, AVERAGE_VOLUME 
        FROM v_nem_average 
        WHERE day_name LIKE '%Sunday%';
        
    ELSE 
        INSERT INTO LOCAL_RM16 (COMPANY_CODE, SETTLEMENT_CASE_ID,SETTLEMENT_RUN_ID, STATEMENT_TYPE, TNI, METERTYPE, FRMP, LR, MDP, CHANGE_DATE, DAY,TRANSACTION_ID, HH, VOLUME)
        SELECT null, null, null, 'FORECAST', TNI, null, FRMP, LR, null, sysdate, v_day, null, HH, AVERAGE_VOLUME 
        FROM v_nem_average 
        where UPPER(day_name) = UPPER(to_char(trunc(v_day), 'Day'));
        END IF;
  

    V_DAY := V_DAY + 1;
END LOOP;

UPDATE run_table
SET run_end = sysdate,
Outcome = 'SUCCESS',
Remarks = 'Run completed successfully' 
WHERE run_id = v_runLogID;

EXCEPTION
 WHEN moduleRan THEN
        dbms_output.put_line('Check the RUN_TABLE. Module ran in the last half hour, handled in main block');

END;

-----------------------------------------------------------------

/*
    This module generate an XML file and store it in the desire directories
*/

PROCEDURE  XML_Generate IS 
v_file            utl_file.file_type;
v_utlFileName     VARCHAR2(35);
v_myDir           VARCHAR2(35) := 'U13058906_DIR'; 
Ctx               DBMS_XMLGEN.ctxHandle;
xml               CLOB := NULL;
temp_xml          CLOB := NULL;
v_query_date      varchar2(25);
QUERY    VARCHAR2(2000);
BEGIN

SELECT TO_CHAR(sysdate + 2, 'DD-MON-YYYY') INTO v_query_date FROM dual;

QUERY  := 'SELECT tni, sum(volume) tni_total 
                              FROM LOCAL_RM16
                              WHERE DAY = '''||v_query_date||''' GROUP BY tni';


--SELECT TO_CHAR(sysdate + 2, 'DD-MON-YYYY') INTO v_query_date FROM dual;
--SELECT 'U13058906_' || TO_CHAR(sysdate, 'DD-MON-YYYY') ||'.xml' INTO v_utlFileName FROM dual;
SELECT 'hola_amigos.xml' INTO v_utlFileName FROM dual;
dbms_output.put_line(query);
   Ctx := DBMS_XMLGEN.newContext(QUERY);
   DBMS_XMLGen.setRowsetTag( Ctx, 'ROWSETTAG' );
   DBMS_XMLGen.setRowTag( Ctx, 'ROWTAG' );
   temp_xml := DBMS_XMLGEN.getXML(Ctx);
--
        IF temp_xml IS NOT NULL THEN
            IF xml IS NOT NULL THEN
                DBMS_LOB.APPEND( xml, temp_xml );
            ELSE
                xml := temp_xml;
            END IF;
        END IF;
--
        DBMS_XMLGEN.closeContext( Ctx );
        dbms_output.put_line(substr(xml, 1, 1950));
        v_file := utl_file.fopen (v_myDir ,v_utlFileName, 'W');
        utl_file.put_line(v_file, xml);
        utl_file.fclose(v_file);

END;

--

END PKG_2020Main;
