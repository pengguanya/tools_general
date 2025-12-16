#!/usr/bin/env python3
import pandas as pd
import xml.etree.ElementTree as ET
import sys
import os
import argparse
import warnings

# Suppress warnings to keep output clean
warnings.filterwarnings("ignore")

def _parse_xml_spreadsheet(file_path):
    """
    Parses 'XML Spreadsheet 2003' format.
    Handles 'Ragged' files where title rows are shorter than data rows.
    """
    try:
        namespaces = {
            'ss': 'urn:schemas-microsoft-com:office:spreadsheet',
        }
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Find Worksheet or Table
        worksheet = root.find('.//ss:Worksheet', namespaces)
        if worksheet is None:
            rows = root.findall('.//ss:Row', namespaces)
        else:
            rows = worksheet.findall('.//ss:Table/ss:Row', namespaces)

        data = []
        for row in rows:
            row_data = []
            col_index = 0
            
            # Extract cells
            for cell in row.findall('ss:Cell', namespaces):
                # Handle 'Index' attribute (skipped empty columns)
                index_attr = cell.get('{urn:schemas-microsoft-com:office:spreadsheet}Index')
                if index_attr:
                    target_index = int(index_attr) - 1
                    while col_index < target_index:
                        row_data.append(None)
                        col_index += 1
                
                # Get Data Value
                data_tag = cell.find('ss:Data', namespaces)
                val = data_tag.text if data_tag is not None else ""
                row_data.append(val)
                col_index += 1
            data.append(row_data)

        if not data:
            return pd.DataFrame()

        # --- FIX: Normalize Row Widths ---
        # 1. Find the widest row in the entire file (the actual data width)
        max_columns = max(len(row) for row in data)

        # 2. Pad every row to match max_columns
        # This prevents the "16 columns passed, data had 200" error
        for row in data:
            if len(row) < max_columns:
                row.extend([None] * (max_columns - len(row)))

        # 3. Heuristic: Determine Header
        # If the first row is as wide as the data, treat it as a header.
        # If the first row is shorter (metadata/title), treat everything as raw data.
        if len(data[0]) == max_columns:
             # Looks like a clean table
            headers = data[0]
            # Ensure unique headers
            headers = [h if h else f"Unnamed_{i}" for i, h in enumerate(headers)]
            return pd.DataFrame(data[1:], columns=headers)
        else:
            # Looks like a report with a title at the top. 
            # Return raw grid (headers will be 0, 1, 2...) to avoid losing data.
            return pd.DataFrame(data)

    except ET.ParseError:
        return None

def main():
    parser = argparse.ArgumentParser(description="Convert Excel/XML-2003 to CSV via stdout.")
    parser.add_argument("filename", help="Path to the Excel file")
    args = parser.parse_args()

    if not os.path.exists(args.filename):
        sys.stderr.write(f"Error: File '{args.filename}' not found.\n")
        sys.exit(1)

    # Attempt 1: Standard Pandas (for real .xlsx or .xls)
    try:
        df = pd.read_excel(args.filename)
        # If successful, print
        df.to_csv(sys.stdout, index=False)
        
    except Exception:
        # Attempt 2: XML Fallback (for XML-2003 masked as .xls)
        df = _parse_xml_spreadsheet(args.filename)
        
        if df is None:
            sys.stderr.write(f"Error: Could not read '{args.filename}'. Format unknown or corrupted.\n")
            sys.exit(1)
        
        # If we fell back to raw XML parsing because of messy headers, 
        # we print without an index, but we might have integer headers (0, 1, 2...)
        # You can grep/sed these out later if needed.
        df.to_csv(sys.stdout, index=False)

if __name__ == "__main__":
    main()
