CREATE OR REPLACE PACKAGE PKG_2020Main AS

-- Package: PKG_2020Main
-- Author: Yue Lei Theodora Ho
-- Student ID: 13058906
-- Date: 5 June 2020

/*
    Description:
    This package contains the code for Database Programming (31253)
    Assignment.
    It will generate forecast of electricity consumption data for 
    the future 14 days.
    
    The package uses data from V_NEM_RM16 table.
    The ouput prediction is in LOCAL_RM16 table.
    
*/

PROCEDURE RM16_FORECAST (p_date IN DATE DEFAULT SYSDATE);

END PKG_2020Main;
